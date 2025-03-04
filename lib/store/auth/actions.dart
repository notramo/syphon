import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';

import 'package:device_info/device_info.dart';

import 'package:redux/redux.dart';
import 'package:redux_thunk/redux_thunk.dart';
import 'package:syphon/global/libs/jack/index.dart';

import 'package:syphon/global/libs/matrix/auth.dart';
import 'package:syphon/global/libs/matrix/errors.dart';
import 'package:syphon/global/libs/matrix/index.dart';
import 'package:syphon/global/libs/matrix/utils.dart';
import 'package:syphon/global/notifications.dart';
import 'package:syphon/global/print.dart';
import 'package:syphon/global/strings.dart';
import 'package:syphon/global/values.dart';
import 'package:syphon/store/alerts/actions.dart';
import 'package:syphon/store/auth/context/actions.dart';
import 'package:syphon/store/auth/credential/model.dart';
import 'package:syphon/store/auth/homeserver/actions.dart';
import 'package:syphon/store/auth/homeserver/model.dart';
import 'package:syphon/store/crypto/actions.dart';
import 'package:syphon/store/events/actions.dart';
import 'package:syphon/store/index.dart';
import 'package:syphon/store/media/actions.dart';
import 'package:syphon/store/rooms/actions.dart';
import 'package:syphon/store/search/actions.dart';
import 'package:syphon/store/settings/actions.dart';
import 'package:syphon/store/settings/devices-settings/model.dart';
import 'package:syphon/store/settings/notification-settings/remote/actions.dart';
import 'package:syphon/store/sync/actions.dart';
import 'package:syphon/store/sync/background/storage.dart';
import 'package:syphon/store/user/actions.dart';
import 'package:uni_links/uni_links.dart';
import 'package:url_launcher/url_launcher.dart';
import '../user/model.dart';

class SetLoading {
  final bool? loading;
  SetLoading({this.loading});
}

class SetCreating {
  final bool? creating;
  SetCreating({this.creating});
}

class SetUser {
  final User user;
  SetUser({required this.user});
}

class SetClientSecret {
  final String clientSecret;
  SetClientSecret({required this.clientSecret});
}

class SetHostname {
  final String? hostname;
  SetHostname({this.hostname});
}

class SetHomeserver {
  final Homeserver? homeserver;
  SetHomeserver({this.homeserver});
}

class SetUsername {
  final String? username;
  SetUsername({this.username});
}

class SetUsernameValid {
  final bool? valid;
  SetUsernameValid({this.valid});
}

class SetStopgap {
  final bool? stopgap;
  SetStopgap({this.stopgap});
}

class SetPassword {
  final String? password;
  SetPassword({this.password});
}

class SetPasswordCurrent {
  final String? password;
  SetPasswordCurrent({this.password});
}

class SetPasswordConfirm {
  final String? password;
  SetPasswordConfirm({this.password});
}

class SetPasswordValid {
  final bool? valid;
  SetPasswordValid({this.valid});
}

class SetEmail {
  final String? email;
  SetEmail({this.email});
}

class SetEmailValid {
  final bool? valid;
  SetEmailValid({this.valid});
}

class SetEmailAvailability {
  final bool? available;
  SetEmailAvailability({this.available});
}

class SetAgreement {
  final bool? agreement;
  SetAgreement({this.agreement});
}

class SetCaptcha {
  final bool? completed;
  SetCaptcha({this.completed});
}

class SetUsernameAvailability {
  final bool? availability;
  SetUsernameAvailability({this.availability});
}

class SetAuthObserver {
  final StreamController? authObserver;
  SetAuthObserver({this.authObserver});
}

class SetSession {
  final String? session;
  SetSession({this.session});
}

class SetCompleted {
  final List<String>? completed;
  SetCompleted({this.completed});
}

class SetCredential {
  final Credential? credential;
  SetCredential({this.credential});
}

class SetVerificationNeeded {
  final bool? needed;
  SetVerificationNeeded({this.needed});
}

class SetInteractiveAuths {
  final Map? interactiveAuths;
  SetInteractiveAuths({this.interactiveAuths});
}

class ResetUser {}

class ResetOnboarding {}

class ResetAuthStore {}

class ResetSession {}

late StreamSubscription _sub;

ThunkAction<AppState> initDeepLinks() => (Store<AppState> store) async {
      try {
        if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
          return;
        }

        _sub = uriLinkStream.listen((Uri? uri) {
          final token = uri!.queryParameters['loginToken'];
          if (store.state.authStore.user.accessToken == null) {
            store.dispatch(loginUserSSO(token: token));
          }
        }, onError: (err) {
          printError('[streamUniLinks] error $err');
        });
      } on PlatformException {
        addAlert(
          origin: 'initDeepLinks',
          message: 'Failed to SSO Login, please try again later or contact support',
        );
        // Handle exception by warning the user their action did not succeed
        // return?
      }
    };

ThunkAction<AppState> disposeDeepLinks() => (Store<AppState> store) async {
      try {
        _sub.cancel();
      } catch (error) {}
    };

ThunkAction<AppState> startAuthObserver() {
  return (Store<AppState> store) async {
    final authObserver = store.state.authStore.authObserver;

    if (authObserver != null && !authObserver.isClosed) {
      throw 'Cannot call startAuthObserver with an existing instance';
    }

    store.dispatch(SetAuthObserver(
      authObserver: StreamController<User?>.broadcast(),
    ));

    onAuthStateChanged(User? user) async {
      if (user != null && user.accessToken != null) {
        await store.dispatch(fetchAuthUserProfile());
        await store.dispatch(fetchDevices());

        // init encryption for E2EE
        await store.dispatch(initKeyEncryption(user));

        // Run for new authed user without a proper sync
        if (store.state.syncStore.lastSince == null) {
          await store.dispatch(initialSync());
        }

        // init notifications
        globalNotificationPluginInstance = await initNotifications(
          onSelectNotification: (String? payload) {
            dismissAllNotifications(
              pluginInstance: globalNotificationPluginInstance,
            );

            saveNotificationsUnchecked({});

            return Future.value(true);
          },
          onSaveToken: (token) {
            store.dispatch(setPusherDeviceToken(token));
          },
        );

        if (store.state.settingsStore.notificationSettings.enabled) {
          store.dispatch(startNotifications());
        }

        // start syncing for user
        await store.dispatch(startSyncObserver());
      } else {
        // wipe sensitive redux state
        await store.dispatch(ResetRooms());
        await store.dispatch(ResetEvents());
        await store.dispatch(ResetUsers());
        await store.dispatch(ResetCrypto());
        await store.dispatch(ResetAuthStore());
        await store.dispatch(ResetSync());
      }

      // reset client secret
      store.dispatch(initClientSecret());
    }

    // set auth state listener
    store.state.authStore.onAuthStateChanged.listen(
      onAuthStateChanged,
    );
  };
}

ThunkAction<AppState> stopAuthObserver() {
  return (Store<AppState> store) async {
    final authObserver = store.state.authStore.authObserver;

    if (authObserver != null) {
      authObserver.close();
    }
  };
}

/// Generate Device Id
///
/// Used in matrix to distinguish devices
/// for encryption and verification
ThunkAction<AppState> generateDeviceId({String? salt}) {
  return (Store<AppState> store) async {
    final defaultId = Random.secure().nextInt(1 << 31).toString();

    try {
      final deviceInfoPlugin = DeviceInfoPlugin();

      var deviceId;

      // Find a unique value for the type of device
      if (Platform.isAndroid) {
        final info = await deviceInfoPlugin.androidInfo;
        deviceId = info.androidId;
      } else if (Platform.isIOS) {
        final info = await deviceInfoPlugin.iosInfo;
        deviceId = info.identifierForVendor;
      } else {
        deviceId = Random.secure().nextInt(1 << 31).toString();
      }

      // hash it
      final deviceIdDigest = sha256.convert(utf8.encode(deviceId + salt));

      final deviceIdHash =
          base64.encode(deviceIdDigest.bytes).toUpperCase().replaceAll(RegExp(r'[^\w]'), '').substring(0, 10);

      return Device(
        deviceId: deviceIdHash,
        displayName: Values.appDisplayName,
      );
    } catch (error) {
      debugPrint('[generateDeviceId] $error');
      return Device(
        deviceId: defaultId,
        displayName: Values.appDisplayName,
      );
    }
  };
}

ThunkAction<AppState> loginUser() {
  return (Store<AppState> store) async {
    store.dispatch(SetLoading(loading: true));

    try {
      // Wait at least 2 seconds until you can attempt to login again
      // includes processing time by authenticating matrix server
      store.dispatch(SetStopgap(stopgap: true));

      // prevents people spamming the login if it were to fail repeatedly
      Timer(Duration(seconds: 2), () {
        store.dispatch(SetStopgap(stopgap: false));
      });

      var homeserver = store.state.authStore.homeserver;
      final username = store.state.authStore.username.replaceAll('@', '');
      final password = store.state.authStore.password;
      final protocol = store.state.authStore.protocol;

      final Device device = await store.dispatch(
        generateDeviceId(salt: username),
      );

      try {
        homeserver = await store.dispatch(fetchBaseUrl(homeserver: homeserver));
      } catch (error) {/* still attempt login */}

      final data = await MatrixApi.loginUser(
        protocol: protocol,
        type: MatrixAuthTypes.PASSWORD,
        homeserver: homeserver.baseUrl!,
        username: username,
        password: password,
        deviceId: device.deviceId,
        deviceName: device.displayName,
      );

      if (data['errcode'] == 'M_FORBIDDEN') {
        throw 'Invalid credentials, confirm and try again';
      }

      if (data['errcode'] != null) {
        throw data['error'];
      }

      final user = User.fromMatrix(data).copyWith(
        homeserver: homeserver.baseUrl,
      );

      await store.dispatch(SetUser(user: user));
      await store.dispatch(addAvailableUser(user));

      final contextObserver = store.state.authStore.contextObserver;

      contextObserver?.add(
        store.state.authStore.user,
      );

      store.dispatch(ResetOnboarding());
    } catch (error) {
      store.dispatch(addAlert(
        origin: 'loginUser',
        message: error.toString(),
        error: error,
      ));
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

ThunkAction<AppState> loginUserSSO({String? token}) {
  return (Store<AppState> store) async {
    store.dispatch(SetLoading(loading: true));

    try {
      final homeserver = await store.dispatch(
        fetchBaseUrl(homeserver: store.state.authStore.homeserver),
      );

      if (token == null) {
        final ssoUrl = 'https://${homeserver.baseUrl}${Values.matrixSSOUrl}';

        if (await canLaunch(ssoUrl)) {
          return await launch(ssoUrl, forceSafariVC: false);
        } else {
          throw 'Could not launch $ssoUrl';
        }
      }

      final username = store.state.authStore.username;

      // Wait at least 2 seconds until you can attempt to login again
      // includes processing time by authenticating matrix server
      store.dispatch(SetStopgap(stopgap: true));

      // prevents people spamming the login if it were to fail repeatedly
      Timer(Duration(seconds: 2), () {
        store.dispatch(SetStopgap(stopgap: false));
      });

      final Device device = await store.dispatch(
        generateDeviceId(salt: username),
      );

      final data = await MatrixApi.loginUserToken(
        protocol: store.state.authStore.protocol,
        type: MatrixAuthTypes.TOKEN,
        homeserver: homeserver.baseUrl,
        token: token,
        session: null,
        deviceId: device.deviceId,
        deviceName: device.displayName,
      );

      if (data['errcode'] == 'M_FORBIDDEN') {
        throw 'Invalid credentials, confirm and try again';
      }

      if (data['errcode'] != null) {
        throw data['error'];
      }

      final user = User.fromMatrix(data).copyWith(
        homeserver: homeserver.baseUrl,
      );

      await store.dispatch(SetUser(user: user));
      await store.dispatch(addAvailableUser(user));

      store.state.authStore.contextObserver?.add(
        store.state.authStore.user,
      );

      store.dispatch(ResetOnboarding());
    } catch (error) {
      store.dispatch(addAlert(
        origin: 'loginUserSSO',
        message: error.toString(),
        error: error,
      ));
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

ThunkAction<AppState> logoutUser() {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetLoading(loading: true));

      await store.dispatch(stopSyncObserver());

      // copy user data in case store updates occur
      final user = store.state.authStore.user.copyWith();

      // attempt to logout of Matrix if even possible
      if (user.homeserver != null && user.accessToken != null) {
        final data = await MatrixApi.logoutUser(
          protocol: store.state.authStore.protocol,
          homeserver: user.homeserver,
          accessToken: user.accessToken,
        );

        if (data['errcode'] != null) {
          if (data['errcode'] != MatrixErrors.unknown_token) {
            throw Exception(data['error']);
          }
        }
      }

      // Remove this user from available multiaccounts
      await store.dispatch(removeAvailableUser(user));

      // Attempt to switch to another user if session is present
      // final nextAvailableUser = store.state.authStore.availableUsers;
      // final nextUser = nextAvailableUser.isNotEmpty ? nextAvailableUser.first : null;

      store.state.authStore.contextObserver?.add(null);
    } catch (error) {
      store.dispatch(addAlert(
        origin: 'logoutUser',
        error: error,
        message: error.toString(),
      ));
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

ThunkAction<AppState> fetchAuthUserProfile() {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetLoading(loading: true));

      final data = await MatrixApi.fetchUserProfile(
        protocol: store.state.authStore.protocol,
        homeserver: store.state.authStore.user.homeserver,
        accessToken: store.state.authStore.user.accessToken,
        userId: store.state.authStore.currentUser.userId,
      );

      await store.dispatch(SetUser(
        user: store.state.authStore.currentUser.copyWith(
          displayName: data['displayname'],
          avatarUri: data['avatar_url'],
        ),
      ));
    } catch (error) {
      store.dispatch(addAlert(
        origin: 'fetchAuthUserProfile',
        error: error,
        message: 'Failed to fetch current user profile',
      ));
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

ThunkAction<AppState> checkUsernameAvailability() {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetLoading(loading: true));

      final data = await MatrixApi.checkUsernameAvailability(
        protocol: store.state.authStore.protocol,
        homeserver: store.state.authStore.homeserver.baseUrl,
        username: store.state.authStore.username,
      );

      if (data['errcode'] != null) {
        throw data['error'];
      }

      store.dispatch(SetUsernameAvailability(
        availability: data['available'],
      ));
    } catch (error) {
      debugPrint('[checkUsernameAvailability] $error');
      store.dispatch(SetUsernameAvailability(availability: false));
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

ThunkAction<AppState> setInteractiveAuths({Map? auths}) {
  return (Store<AppState> store) async {
    try {
      final List<String> completed = List<String>.from(auths!['completed'] ?? []);

      await store.dispatch(SetSession(session: auths['session']));
      await store.dispatch(SetCompleted(completed: completed));
      await store.dispatch(SetInteractiveAuths(interactiveAuths: auths));

      if (auths['flows'] != null && auths['flows'].length > 0) {
        // Set completed if certain flows exist
        final List<dynamic> stages = auths['flows'][0]['stages'];

        // Find next stage that needs to be completed
        final currentStage = stages.firstWhere(
          (stage) => !completed.contains(stage),
        );

        if (currentStage.length > 0) {
          debugPrint('[SetCredential] $currentStage');
          store.dispatch(SetCredential(
            credential: Credential(
              type: currentStage,
              params: auths['params'],
            ),
          ));
        }
      }
    } catch (error) {
      debugPrint('[setInteractiveAuth] $error');
    }
  };
}

///
/// Check Password reset Verification
///
/// TODO: find a way to check if they've clicked the link
/// without invalidating the token, sending a blank password
/// doesn't work
ThunkAction<AppState> checkPasswordResetVerification({
  int sendAttempt = 1,
  String? password,
}) {
  return (Store<AppState> store) async {
    try {
      final homeserver = store.state.authStore.homeserver.baseUrl;
      final clientSecret = store.state.authStore.clientSecret;
      final session = store.state.authStore.authSession;
      final protocol = store.state.authStore.protocol;

      final data = await MatrixApi.resetPassword(
        protocol: protocol,
        homeserver: homeserver,
        clientSecret: clientSecret,
        sendAttempt: sendAttempt,
        passwordNew: password,
        session: session,
      );

      if (data['errcode'] != null && data['errcode'] == MatrixErrors.not_authorized) {
        throw data['error'];
      }

      await store.dispatch(addConfirmation(
        message: 'Verification Confirmed',
      ));

      store.dispatch(ResetAuthStore());
      return true;
    } catch (error) {
      store.dispatch(addAlert(
        origin: 'checkPasswordResetVerification',
        error: error,
        message: 'Please click the emailed verify link before continuing',
      ));
      return false;
    }
  };
}

ThunkAction<AppState> resetPassword({int sendAttempt = 1, String? password}) {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetLoading(loading: true));

      final homeserver = store.state.authStore.homeserver.baseUrl;
      final clientSecret = store.state.authStore.clientSecret;
      final session = store.state.authStore.authSession;
      final protocol = store.state.authStore.protocol;

      final data = await MatrixApi.resetPassword(
        protocol: protocol,
        homeserver: homeserver,
        clientSecret: clientSecret,
        sendAttempt: sendAttempt,
        passwordNew: password,
        session: session,
      );

      if (data['errcode'] != null) {
        throw data['error'];
      }

      store.dispatch(ResetOnboarding());

      await store.dispatch(addConfirmation(
        message: 'Successfully reset your password!',
      ));
      return true;
    } catch (error) {
      store.dispatch(addAlert(origin: 'resetPassword', error: error));
      return false;
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

ThunkAction<AppState> sendPasswordResetEmail({int sendAttempt = 1}) {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetLoading(loading: true));

      final email = store.state.authStore.email;
      final homeserver = store.state.authStore.homeserver.baseUrl;
      final clientSecret = store.state.authStore.clientSecret;

      final data = await MatrixApi.sendPasswordResetEmail(
        protocol: store.state.authStore.protocol,
        homeserver: homeserver,
        clientSecret: clientSecret,
        sendAttempt: sendAttempt,
        email: email,
      );

      if (data['errcode'] != null) {
        throw data['error'];
      }

      store.dispatch(SetSession(session: data['sid']));

      await store.dispatch(addConfirmation(
        message: 'Successfully sent password reset email to $email',
      ));
      return true;
    } catch (error) {
      store.dispatch(addAlert(origin: 'sendPasswordResetEmail', error: error));
      return false;
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

ThunkAction<AppState> submitEmail({int? sendAttempt = 1}) {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetLoading(loading: true));

      final homeserver = store.state.authStore.homeserver.baseUrl;
      final emailSubmitted = store.state.authStore.email;
      final clientSecret = store.state.authStore.clientSecret;
      final currentCredential = store.state.authStore.credential!;
      final protocol = store.state.authStore.protocol;

      if (currentCredential.params!.containsValue(emailSubmitted) && sendAttempt! < 2) {
        return true;
      }

      final data = await MatrixApi.registerEmail(
        protocol: protocol,
        homeserver: homeserver,
        email: store.state.authStore.email,
        clientSecret: clientSecret,
        sendAttempt: sendAttempt,
      );

      if (data['errcode'] != null) {
        throw data['error'];
      }

      store.dispatch(SetCredential(
        credential: currentCredential.copyWith(
          params: {
            'sid': data['sid'],
            'client_secret': clientSecret,
            'email_submitted': store.state.authStore.email
          },
        ),
      ));
      return true;
    } catch (error) {
      debugPrint('[submitEmail] $error');
      store.dispatch(SetEmailValid(valid: false));
      store.dispatch(SetEmailAvailability(available: false));
      return false;
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

///
/// Create a user / Attempt creation
///
/// process references are in assets/cheatsheet.md
ThunkAction<AppState> createUser({enableErrors = false}) {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetLoading(loading: true));
      store.dispatch(SetCreating(creating: true));

      final homeserver = store.state.authStore.homeserver.baseUrl;
      final credential = store.state.authStore.credential;
      final session = store.state.authStore.authSession;
      final authType = session != null ? credential!.type : MatrixAuthTypes.DUMMY;
      final authValue = session != null ? credential!.value : null;
      final authParams = session != null ? credential!.params : null;

      final device = await store.dispatch(generateDeviceId(
        salt: store.state.authStore.username,
      ));

      final data = await MatrixApi.registerUser(
        protocol: store.state.authStore.protocol,
        homeserver: homeserver,
        username: store.state.authStore.username,
        password: store.state.authStore.password,
        session: store.state.authStore.authSession,
        authType: authType,
        authValue: authValue,
        authParams: authParams,
        deviceId: device.deviceId,
        deviceName: device.displayName,
      );

      if (data['errcode'] != null) {
        if (data['errcode'] == MatrixErrors.not_authorized && credential!.type == MatrixAuthTypes.EMAIL) {
          store.dispatch(SetVerificationNeeded(needed: true));
          return false;
        }
        throw data['error'];
      }

      if (data['flows'] != null) {
        await store.dispatch(setInteractiveAuths(auths: data));

        final List<dynamic> stages = store.state.authStore.interactiveAuths['flows'][0]['stages'];
        final completed = store.state.authStore.completed;

        // Compare the completed stages to the flow stages provided
        final bool completedAll = stages.fold(true, (hasCompleted, stage) {
          return hasCompleted && completed.contains(stage);
        });

        return completedAll;
      }
      final user = User.fromMatrix(data);

      await store.dispatch(SetUser(user: user));
      await store.dispatch(addAvailableUser(user));

      store.state.authStore.contextObserver?.add(
        store.state.authStore.user,
      );

      store.dispatch(ResetOnboarding());
      return true;
    } catch (error) {
      printError('[createUser] error $error');

      if (enableErrors) {
        store.dispatch(addAlert(
          origin: 'createUser',
          message: error.toString(),
          error: error,
        ));
      }
      return false;
    } finally {
      store.dispatch(SetCreating(creating: false));
      store.dispatch(SetLoading(loading: false));
    }
  };
}

ThunkAction<AppState> updatePassword(String password) {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetLoading(loading: true));

      var data;

      // Call just to get interactive auths
      data = await MatrixApi.updatePassword(
        protocol: store.state.authStore.protocol,
        homeserver: store.state.authStore.user.homeserver,
        accessToken: store.state.authStore.user.accessToken,
        password: password,
      );

      if (data['errcode'] != null) {
        throw data['error'];
      }

      if (data['flows'] != null) {
        await store.dispatch(setInteractiveAuths(auths: data));

        data = await MatrixApi.updatePassword(
          protocol: store.state.authStore.protocol,
          homeserver: store.state.authStore.user.homeserver,
          accessToken: store.state.authStore.user.accessToken,
          userId: store.state.authStore.user.userId,
          session: store.state.authStore.authSession,
          password: password,
          currentPassword: store.state.authStore.passwordCurrent,
        );
      }

      if (data['errcode'] != null) {
        throw data['error'];
      }

      store.dispatch(addConfirmation(
        message: 'Password updated successfully',
      ));

      return true;
    } catch (error) {
      store.dispatch(addAlert(
        origin: 'updatePassword',
        message: 'Failed to update passwod',
        error: error,
      ));
      return false;
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

ThunkAction<AppState> updateDisplayName(String newDisplayName) {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetLoading(loading: true));

      final data = await MatrixApi.updateDisplayName(
        protocol: store.state.authStore.protocol,
        homeserver: store.state.authStore.user.homeserver,
        accessToken: store.state.authStore.user.accessToken,
        userId: store.state.authStore.user.userId,
        displayName: newDisplayName,
      );

      if (data['errcode'] != null) {
        throw data['error'];
      }
      return true;
    } catch (error) {
      store.dispatch(
        addAlert(origin: 'updateDisplayName', message: error.toString()),
      );
      return false;
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

ThunkAction<AppState> updateAvatar({File? localFile}) {
  return (Store<AppState> store) async {
    try {
      store.dispatch(SetLoading(loading: true));

      final String? displayName = store.state.authStore.user.displayName;

      final data = await store.dispatch(uploadMedia(
        localFile: localFile,
        mediaName: '${displayName}_profile_photo',
      ));

      await store.dispatch(updateAvatarUri(
        mxcUri: data['content_uri'],
      ));

      return true;
    } catch (error) {
      store.dispatch(
        addAlert(origin: 'updateAvatar', message: error.toString()),
      );
      return false;
    } finally {
      store.dispatch(SetLoading(loading: false));
    }
  };
}

/// updateAvatarUri
///
/// Helper action - no try catch as it's meant to be
/// included in other update actions
ThunkAction<AppState> updateAvatarUri({String? mxcUri}) {
  return (Store<AppState> store) async {
    final data = await MatrixApi.updateAvatarUri(
      protocol: store.state.authStore.protocol,
      homeserver: store.state.authStore.user.homeserver,
      accessToken: store.state.authStore.user.accessToken,
      userId: store.state.authStore.user.userId,
      avatarUri: mxcUri,
    );

    if (data['errcode'] != null) {
      throw data['error'];
    }
  };
}

ThunkAction<AppState> setLoading(bool loading) {
  return (Store<AppState> store) async {
    store.dispatch(SetLoading(loading: loading));
  };
}

/// Update current interactive auth attempt
ThunkAction<AppState> updateCredential({
  String? type,
  String? value,
  Map<String, String>? params,
}) {
  return (Store<AppState> store) {
    try {
      final currentCredential = store.state.authStore.credential!;
      store.dispatch(SetCredential(
        credential: currentCredential.copyWith(
          type: type,
          value: value,
          params: params,
        ),
      ));
    } catch (error) {
      debugPrint('[updateCredential] $error');
    }
  };
}

ThunkAction<AppState> resetInteractiveAuth() {
  return (Store<AppState> store) async {
    store.dispatch(ResetSession());
  };
}

ThunkAction<AppState> selectHomeserver({String? hostname}) {
  return (Store<AppState> store) async {
    final Homeserver homeserver = await store.dispatch(
      fetchHomeserver(hostname: hostname),
    );

    store.dispatch(setHomeserver(homeserver: homeserver));
    store.dispatch(setHostname(hostname: hostname));

    return homeserver.valid;
  };
}

ThunkAction<AppState> deactivateAccount() => (Store<AppState> store) async {
      try {
        store.dispatch(SetLoading(loading: true));

        final currentCredential = store.state.authStore.credential ?? Credential();

        final user = store.state.authStore.user;
        final idServer = user.idserver;
        final homeserver = user.homeserver;

        final data = await MatrixApi.deactivateUser(
          protocol: store.state.authStore.protocol,
          homeserver: homeserver,
          accessToken: user.accessToken,
          identityServer: idServer ?? homeserver,
          session: store.state.authStore.authSession,
          userId: user.userId,
          authType: MatrixAuthTypes.PASSWORD,
          authValue: currentCredential.value,
        );

        if (data['errcode'] != null) {
          throw data['error'];
        }

        if (data['flows'] != null) {
          return store.dispatch(setInteractiveAuths(auths: data));
        }

        await store.dispatch(removeAvailableUser(user));

        store.state.authStore.contextObserver?.add(null);
      } catch (error) {
        store.dispatch(addAlert(
          error: error,
          message: error.toString(),
          origin: 'deactivateAccount',
        ));
      } finally {
        store.dispatch(SetLoading(loading: false));
      }
    };

ThunkAction<AppState> fetchHomeservers() {
  return (Store<AppState> store) async {
    store.dispatch(SetLoading(loading: true));

    final homeserversJson = await JackApi.fetchPublicServers();

    // parse homeserver data
    final List<Homeserver> homserverData = homeserversJson.map((data) {
      final hostname = data['hostname'].toString().split('.');
      final hostnameBase = hostname.length > 1
          ? '${hostname[hostname.length - 2]}.${hostname[hostname.length - 1]}'
          : hostname[0];

      return Homeserver(
        hostname: hostnameBase,
        location: data['location'] ?? '',
        description: data['description'] ?? '',
        usersActive: data['users_active'] != null ? data['users_active'].toString() : null,
        roomsTotal: data['public_room_count'] != null ? data['public_room_count'].toString() : null,
        founded: data['online_since'] != null ? data['online_since'].toString() : '',
        responseTime: data['last_response_time'] != null ? data['last_response_time'].toString() : '',
      );
    }).toList();

    // set homeservers without cached photo url
    await store.dispatch(SetHomeservers(homeservers: homserverData));

    // find favicons for all the homeservers
    final homeservers = await Future.wait(
      homserverData.map((homeserver) async {
        final url = await fetchFavicon(url: homeserver.hostname);
        try {
          final uri = Uri.parse(url!);
          final response = await http.get(uri);

          if (response.statusCode == 200) {
            return homeserver.copyWith(photoUrl: url);
          }
        } catch (error) {/* noop */}

        return homeserver;
      }),
    );

    // set the homeservers and finish loading
    await store.dispatch(SetHomeservers(homeservers: homeservers));
    store.dispatch(SetLoading(loading: false));
  };
}

ThunkAction<AppState> fetchHomeserver({String? hostname}) {
  return (Store<AppState> store) async {
    store.dispatch(SetLoading(loading: true));
    var homeserver = Homeserver(hostname: hostname);

    // fetch homeserver icon url
    try {
      final iconUrl = await fetchFavicon(url: homeserver.hostname);

      homeserver = homeserver.copyWith(photoUrl: iconUrl);
    } catch (error) {
      printError('[selectHomserver] $error');
    }

    // fetch homeserver well-known
    try {
      homeserver = await store.dispatch(fetchBaseUrl(homeserver: homeserver));
      if (!homeserver.valid) {
        throw Exception(Strings.alertCheckHomeserver);
      }
    } catch (error) {
      printError('[selectHomserver] $error');
      addInfo(message: error.toString());

      store.dispatch(SetLoading(loading: false));

      return Homeserver(
        valid: false,
        baseUrl: hostname,
        hostname: hostname,
        loginType: MatrixAuthTypes.DUMMY,
      );
    }

    // fetch homeserver login type
    try {
      final response = await MatrixApi.loginType(
            protocol: store.state.authStore.protocol,
            homeserver: homeserver.baseUrl!,
          ) ??
          {};

      // { "flows": [ { "type": "m.login.sso" }, { "type": "m.login.token" } ]}
      final loginTypes = (response['flows'] as List).map((flow) => flow['type'] as String).toList();

      homeserver = homeserver.copyWith(loginTypes: loginTypes);
    } catch (error) {}

    store.dispatch(SetLoading(loading: false));
    return homeserver;
  };
}

ThunkAction<AppState> initClientSecret({String? hostname}) => (Store<AppState> store) {
      store.dispatch(SetClientSecret(
        clientSecret: generateClientSecret(length: 24),
      ));
    };

ThunkAction<AppState> setHostname({String? hostname}) => (Store<AppState> store) {
      store.dispatch(SetHostname(hostname: hostname!.trim()));
    };

ThunkAction<AppState> setHomeserver({Homeserver? homeserver}) => (Store<AppState> store) {
      store.dispatch(SetHomeserver(homeserver: homeserver));
    };

ThunkAction<AppState> setEmail({String? email}) {
  return (Store<AppState> store) {
    final validEmail = RegExp(Values.emailRegex).hasMatch(email!);

    store.dispatch(SetEmailValid(
      valid: email != null && email.isNotEmpty && validEmail,
    ));
    store.dispatch(SetEmail(email: email));
    store.dispatch(SetEmailAvailability(available: true));
  };
}

ThunkAction<AppState> setUsername({String? username}) {
  return (Store<AppState> store) {
    store.dispatch(SetUsernameValid(valid: username != null && username.isNotEmpty));
    store.dispatch(SetUsername(username: username!.trim()));
  };
}

ThunkAction<AppState> resolveUsername({String? username}) {
  return (Store<AppState> store) {
    final hostname = store.state.authStore.hostname;
    final homeserver = store.state.authStore.homeserver;

    var formatted = username!.trim();
    if (formatted.length > 1) {
      formatted = formatted.replaceFirst('@', '', 1);
    }
    final alias = formatted.split(':');

    store.dispatch(setUsername(username: alias[0]));

    // If user enters full username, make sure to set homeserver
    if (username.contains(':')) {
      store.dispatch(setHostname(hostname: alias[1]));
    } else {
      if (!hostname.contains('.')) {
        store.dispatch(setHostname(
          hostname: homeserver.hostname ?? Values.homeserverDefault,
        ));
      }
    }
  };
}

ThunkAction<AppState> setLoginPassword({String? password}) => (Store<AppState> store) {
      store.dispatch(SetPassword(password: password));
      store.dispatch(SetPasswordValid(
        valid: password != null && password.isNotEmpty,
      ));
    };

ThunkAction<AppState> setPassword({
  required String password,
  bool ignoreConfirm = false,
}) {
  return (Store<AppState> store) {
    store.dispatch(SetPassword(password: password));

    final currentPassword = store.state.authStore.password;
    final currentConfirm = store.state.authStore.passwordConfirm;

    store.dispatch(SetPasswordValid(
      valid: (currentPassword == currentConfirm || ignoreConfirm) && password.length > 8,
    ));
  };
}

ThunkAction<AppState> setPasswordCurrent({String? password}) {
  return (Store<AppState> store) {
    store.dispatch(SetPasswordCurrent(password: password));
  };
}

ThunkAction<AppState> setPasswordConfirm({String? password}) {
  return (Store<AppState> store) {
    store.dispatch(SetPasswordConfirm(password: password));

    final currentPassword = store.state.authStore.password;
    final currentConfirm = store.state.authStore.passwordConfirm;

    store.dispatch(SetPasswordValid(
      valid: password != null && password.length > 6 && currentPassword == currentConfirm,
    ));
  };
}

ThunkAction<AppState> toggleAgreement({bool? agreement}) {
  return (Store<AppState> store) {
    store.dispatch(SetAgreement(
      agreement: agreement ?? !store.state.authStore.agreement,
    ));
  };
}

ThunkAction<AppState> toggleCaptcha({bool? completed}) {
  return (Store<AppState> store) async {
    store.dispatch(
      SetCaptcha(completed: completed ?? !store.state.authStore.captcha),
    );
  };
}
