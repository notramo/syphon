import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:equatable/equatable.dart';
import 'package:fab_circular_menu/fab_circular_menu.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:redux/redux.dart';
import 'package:syphon/global/colours.dart';

import 'package:syphon/store/settings/theme-settings/model.dart';
import 'package:syphon/store/events/selectors.dart';
import 'package:syphon/views/navigation.dart';
import 'package:syphon/views/widgets/containers/fabs/fab-circle-expanding.dart';
import 'package:syphon/views/widgets/containers/fabs/fab-bar-expanding.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:syphon/global/assets.dart';
import 'package:syphon/global/dimensions.dart';
import 'package:syphon/global/formatters.dart';
import 'package:syphon/global/strings.dart';

import 'package:syphon/global/values.dart';
import 'package:syphon/store/index.dart';
import 'package:syphon/store/rooms/actions.dart';
import 'package:syphon/global/libs/matrix/constants.dart';
import 'package:syphon/store/events/messages/model.dart';
import 'package:syphon/store/rooms/room/model.dart';
import 'package:syphon/store/rooms/room/selectors.dart';
import 'package:syphon/store/rooms/selectors.dart';
import 'package:syphon/store/settings/chat-settings/model.dart';
import 'package:syphon/store/sync/actions.dart';
import 'package:syphon/store/user/model.dart';
import 'package:syphon/views/home/chat/chat-detail-screen.dart';
import 'package:syphon/views/home/chat/chat-screen.dart';
import 'package:syphon/views/widgets/avatars/avatar-app-bar.dart';
import 'package:syphon/views/widgets/avatars/avatar.dart';
import 'package:syphon/views/widgets/containers/menu-rounded.dart';
import 'package:syphon/views/widgets/containers/fabs/fab-ring.dart';

enum Options { newGroup, markAllRead, inviteFriends, settings, licenses, help }

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<HomeScreen> {
  HomeState() : super();

  final fabKeyRing = GlobalKey<FabCircularMenuState>();
  final fabKeyCircle = GlobalKey<FabBarContainerState>();
  final fabKeyBar = GlobalKey<FabBarContainerState>();

  Room? selectedRoom;
  Map<String, Color> roomColorDefaults = {};

  @protected
  onToggleRoomOptions({Room? room}) {
    setState(() {
      selectedRoom = room;
    });
  }

  @protected
  onDismissMessageOptions() {
    setState(() {
      selectedRoom = null;
    });
  }

  @protected
  Widget buildAppBarRoomOptions({BuildContext? context, _Props? props}) => AppBar(
        backgroundColor: Color(Colours.greyDefault),
        automaticallyImplyLeading: false,
        titleSpacing: 0.0,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              margin: EdgeInsets.only(left: 8),
              child: IconButton(
                icon: Icon(Icons.close),
                color: Colors.white,
                iconSize: Dimensions.buttonAppBarSize,
                onPressed: onDismissMessageOptions,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.info_outline),
            iconSize: Dimensions.buttonAppBarSize,
            tooltip: 'Chat Details',
            color: Colors.white,
            onPressed: () {
              Navigator.pushNamed(
                context!,
                NavigationPaths.chatDetails,
                arguments: ChatDetailsArguments(
                  roomId: selectedRoom!.id,
                  title: selectedRoom!.name,
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.archive),
            iconSize: Dimensions.buttonAppBarSize,
            tooltip: 'Archive Room',
            color: Colors.white,
            onPressed: () async {
              await props!.onArchiveRoom(room: selectedRoom);
              setState(() {
                selectedRoom = null;
              });
            },
          ),
          Visibility(
            visible: true,
            child: IconButton(
              icon: Icon(Icons.exit_to_app),
              iconSize: Dimensions.buttonAppBarSize,
              tooltip: 'Leave Chat',
              color: Colors.white,
              onPressed: () async {
                await props!.onLeaveChat(room: selectedRoom);
                setState(() {
                  selectedRoom = null;
                });
              },
            ),
          ),
          Visibility(
            visible: selectedRoom!.direct,
            child: IconButton(
              icon: Icon(Icons.delete_outline),
              iconSize: Dimensions.buttonAppBarSize,
              tooltip: 'Delete Chat',
              color: Colors.white,
              onPressed: () async {
                await props!.onDeleteChat(room: selectedRoom);
                setState(() {
                  selectedRoom = null;
                });
              },
            ),
          ),
          IconButton(
            icon: Icon(Icons.select_all),
            iconSize: Dimensions.buttonAppBarSize,
            tooltip: 'Select All',
            color: Colors.white,
            onPressed: () {},
          ),
        ],
      );

  @protected
  Widget buildAppBar({required BuildContext context, required _Props props}) => AppBar(
        automaticallyImplyLeading: false,
        brightness: Brightness.dark,
        titleSpacing: 16.00,
        title: Row(
          children: <Widget>[
            AvatarAppBar(
              themeType: props.themeType,
              user: props.currentUser,
              offline: props.offline,
              syncing: props.syncing,
              unauthed: props.unauthed,
              tooltip: 'Profile and Settings',
              onPressed: () {
                Navigator.pushNamed(context, NavigationPaths.settingsProfile);
              },
            ),
            Text(
              Values.appName,
              style: Theme.of(context).textTheme.headline6!.copyWith(
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            color: Colors.white,
            icon: Icon(Icons.search),
            tooltip: 'Search Chats',
            onPressed: () {
              Navigator.pushNamed(context, NavigationPaths.searchAll);
            },
          ),
          RoundedPopupMenu<Options>(
            icon: Icon(Icons.more_vert, color: Colors.white),
            onSelected: (Options result) {
              switch (result) {
                case Options.newGroup:
                  Navigator.pushNamed(context, NavigationPaths.groupCreate);
                  break;
                case Options.markAllRead:
                  props.onMarkAllRead();
                  break;
                case Options.settings:
                  Navigator.pushNamed(context, NavigationPaths.settings);
                  break;
                case Options.help:
                  props.onSelectHelp();
                  break;
                default:
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<Options>>[
              const PopupMenuItem<Options>(
                value: Options.newGroup,
                child: Text('New Group'),
              ),
              const PopupMenuItem<Options>(
                value: Options.markAllRead,
                child: Text('Mark All Read'),
              ),
              const PopupMenuItem<Options>(
                value: Options.inviteFriends,
                enabled: false,
                child: Text('Invite Friends'),
              ),
              const PopupMenuItem<Options>(
                value: Options.settings,
                child: Text('Settings'),
              ),
              const PopupMenuItem<Options>(
                value: Options.help,
                child: Text('Help'),
              ),
            ],
          )
        ],
      );

  @protected
  Widget buildChatList(BuildContext context, _Props props) {
    final rooms = props.rooms;

    final label = props.syncing ? Strings.labelSyncing : Strings.labelMessagesEmpty;

    if (rooms.isEmpty) {
      return Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            constraints: BoxConstraints(
              minWidth: Dimensions.mediaSizeMin,
              maxWidth: Dimensions.mediaSizeMax,
              maxHeight: Dimensions.mediaSizeMin,
            ),
            child: SvgPicture.asset(
              Assets.heroChatNotFound,
              semanticsLabel: Strings.semanticsHomeDefault,
            ),
          ),
          GestureDetector(
            child: Container(
              margin: EdgeInsets.only(bottom: 48),
              padding: EdgeInsets.only(top: 16),
              child: Text(
                label,
                style: Theme.of(context).textTheme.headline6,
              ),
            ),
          ),
        ],
      ));
    }

    return ListView.builder(
      scrollDirection: Axis.vertical,
      itemCount: rooms.length,
      itemBuilder: (BuildContext context, int index) {
        final room = rooms[index];
        final messages = props.messages[room.id] ?? const [];
        final decrypted = props.decrypted[room.id] ?? const [];
        final chatSettings = props.chatSettings[room.id];

        final messageLatest = latestMessage(messages, room: room, decrypted: decrypted);
        final preview = formatPreview(room: room, message: messageLatest);
        final chatName = room.name ?? '';
        final newMessage = messageLatest != null &&
            room.lastRead < messageLatest.timestamp &&
            messageLatest.sender != props.currentUser.userId;

        var backgroundColor;
        var textStyle = TextStyle();
        Color primaryColor = Colors.grey;

        // Check settings for custom color, then check temp cache,
        // or generate new temp color
        if (chatSettings != null) {
          primaryColor = Color(chatSettings.primaryColor);
        } else if (roomColorDefaults.containsKey(room.id)) {
          primaryColor = roomColorDefaults[room.id] ?? primaryColor;
        } else {
          primaryColor = Colours.hashedColor(room.id);
          roomColorDefaults.putIfAbsent(
            room.id,
            () => primaryColor,
          );
        }

        // highlight selected rooms if necessary
        if (selectedRoom != null) {
          if (selectedRoom!.id != room.id) {
            backgroundColor = Theme.of(context).scaffoldBackgroundColor;
          } else {
            backgroundColor = Theme.of(context).primaryColor.withAlpha(128);
          }
        }

        // show draft inidicator if it's an empty room
        if (room.drafting || messages.isEmpty) {
          textStyle = TextStyle(fontStyle: FontStyle.italic);
        }

        if (messages.isNotEmpty && messageLatest != null) {
          // it has undecrypted message contained within
          if (messageLatest.type == EventTypes.encrypted && messageLatest.body!.isEmpty) {
            textStyle = TextStyle(fontStyle: FontStyle.italic);
          }

          if (messageLatest.body == null || messageLatest.body!.isEmpty) {
            textStyle = TextStyle(fontStyle: FontStyle.italic);
          }

          // display message as being 'unread'
          if (newMessage) {
            textStyle = textStyle.copyWith(
              color: Theme.of(context).textTheme.bodyText1!.color,
              fontWeight: FontWeight.w500,
            );
          }
        }

        // GestureDetector w/ animation
        return InkWell(
          onTap: () {
            if (selectedRoom != null) {
              onDismissMessageOptions();
            } else {
              Navigator.pushNamed(
                context,
                NavigationPaths.chat,
                arguments: ChatScreenArguments(roomId: room.id, title: chatName),
              );
            }
          },
          onLongPress: () => onToggleRoomOptions(room: room),
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor, // if selected, color seperately
            ),
            padding: EdgeInsets.symmetric(
              vertical: Theme.of(context).textTheme.subtitle1!.fontSize!,
            ).add(Dimensions.appPaddingHorizontal),
            child: Flex(
              direction: Axis.horizontal,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: Stack(
                    children: [
                      Avatar(
                        uri: room.avatarUri,
                        size: Dimensions.avatarSizeMin,
                        alt: formatRoomInitials(room: room),
                        background: primaryColor,
                      ),
                      Visibility(
                        visible: !room.encryptionEnabled,
                        child: Positioned(
                          bottom: 0,
                          right: 0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              Dimensions.badgeAvatarSize,
                            ),
                            child: Container(
                              width: Dimensions.badgeAvatarSize,
                              height: Dimensions.badgeAvatarSize,
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Icon(
                                Icons.lock_open,
                                color: Theme.of(context).iconTheme.color,
                                size: Dimensions.iconSizeMini,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Visibility(
                        visible: props.roomTypeBadgesEnabled && room.invite,
                        child: Positioned(
                          bottom: 0,
                          right: 0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: Dimensions.badgeAvatarSize,
                              height: Dimensions.badgeAvatarSize,
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Icon(
                                Icons.mail_outline,
                                color: Theme.of(context).iconTheme.color,
                                size: Dimensions.iconSizeMini,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Visibility(
                        visible: newMessage,
                        child: Positioned(
                          top: 0,
                          right: 0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: Dimensions.badgeAvatarSizeSmall,
                              height: Dimensions.badgeAvatarSizeSmall,
                              color: Theme.of(context).accentColor,
                            ),
                          ),
                        ),
                      ),
                      Visibility(
                        visible: props.roomTypeBadgesEnabled && room.type == 'group' && !room.invite,
                        child: Positioned(
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: Dimensions.badgeAvatarSize,
                              height: Dimensions.badgeAvatarSize,
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Icon(
                                Icons.group,
                                color: Theme.of(context).iconTheme.color,
                                size: Dimensions.badgeAvatarSizeSmall,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Visibility(
                        visible: props.roomTypeBadgesEnabled && room.type == 'public' && !room.invite,
                        child: Positioned(
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: Dimensions.badgeAvatarSize,
                              height: Dimensions.badgeAvatarSize,
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: Icon(
                                Icons.public,
                                color: Theme.of(context).iconTheme.color,
                                size: Dimensions.badgeAvatarSize,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  flex: 1,
                  fit: FlexFit.tight,
                  child: Flex(
                    direction: Axis.vertical,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              chatName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyText1,
                            ),
                          ),
                          Text(
                            formatTimestamp(lastUpdateMillis: room.lastUpdate),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w100),
                          ),
                        ],
                      ),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.caption!.merge(
                              textStyle,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  selectActionAlignment(_Props props) {
    if (props.fabLocation == MainFabLocation.Left) {
      return Alignment.bottomLeft;
    }

    return Alignment.bottomRight;
  }

  buildActionFab(_Props props) {
    final fabType = props.fabType;

    if (fabType == MainFabType.Bar) {
      return FabBarExpanding(
        alignment: selectActionAlignment(props),
      );
    }

    // if (fabType == MainFabType.Circle) {
    //   return FabCircleExpanding(
    //     fabKey: fabKeyCircle,
    //     alignment: selectActionAlignment(props),
    //   );
    // }

    return FabRing(
      fabKey: fabKeyRing,
      alignment: selectActionAlignment(props),
    );
  }

  selectActionLocation(_Props props) {
    if (props.fabLocation == MainFabLocation.Left) {
      return FloatingActionButtonLocation.startFloat;
    }

    return FloatingActionButtonLocation.endFloat;
  }

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Props>(
        distinct: true,
        converter: (Store<AppState> store) => _Props.mapStateToProps(store),
        builder: (context, props) {
          var currentAppBar = buildAppBar(
            props: props,
            context: context,
          );

          if (selectedRoom != null) {
            currentAppBar = buildAppBarRoomOptions(
              props: props,
              context: context,
            );
          }

          return Scaffold(
            appBar: currentAppBar as PreferredSizeWidget?,
            floatingActionButton: buildActionFab(props),
            floatingActionButtonLocation: selectActionLocation(props),
            body: Align(
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () {
                        return props.onFetchSyncForced();
                      },
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: onDismissMessageOptions,
                            child: buildChatList(
                              context,
                              props,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _Props extends Equatable {
  final List<Room> rooms;
  final bool? offline;
  final bool syncing;
  final bool unauthed;
  final bool roomTypeBadgesEnabled;
  final User currentUser;
  final ThemeType themeType;
  final MainFabType fabType;
  final MainFabLocation fabLocation;
  final Map<String, ChatSetting> chatSettings;
  final Map<String, List<Message>> messages;
  final Map<String, List<Message>> decrypted;

  final Function onDebug;
  final Function onLeaveChat;
  final Function onDeleteChat;
  final Function onSelectHelp;
  final Function onArchiveRoom;
  final Function onMarkAllRead;
  final Function onFetchSyncForced;

  const _Props({
    required this.rooms,
    required this.themeType,
    required this.offline,
    required this.syncing,
    required this.unauthed,
    required this.messages,
    required this.decrypted,
    required this.currentUser,
    required this.chatSettings,
    required this.fabType,
    required this.fabLocation,
    required this.roomTypeBadgesEnabled,
    required this.onDebug,
    required this.onLeaveChat,
    required this.onDeleteChat,
    required this.onSelectHelp,
    required this.onArchiveRoom,
    required this.onMarkAllRead,
    required this.onFetchSyncForced,
  });

  @override
  List<Object?> get props => [
        rooms,
        messages,
        themeType,
        syncing,
        offline,
        unauthed,
        currentUser,
        chatSettings,
        roomTypeBadgesEnabled,
        fabType,
        fabLocation,
      ];

  static _Props mapStateToProps(Store<AppState> store) => _Props(
        themeType: store.state.settingsStore.themeSettings.themeType,
        rooms: availableRooms(sortPrioritizedRooms(filterBlockedRooms(
          store.state.roomStore.rooms.values.toList(),
          store.state.userStore.blocked,
        ))),
        messages: store.state.eventStore.messages,
        decrypted: store.state.eventStore.messagesDecrypted,
        unauthed: store.state.syncStore.unauthed,
        offline: store.state.syncStore.offline,
        fabType: store.state.settingsStore.themeSettings.mainFabType,
        fabLocation: store.state.settingsStore.themeSettings.mainFabLocation,
        syncing: () {
          final synced = store.state.syncStore.synced;
          final syncing = store.state.syncStore.syncing;
          final offline = store.state.syncStore.offline;
          final backgrounded = store.state.syncStore.backgrounded;
          final loadingRooms = store.state.roomStore.loading;

          final lastAttempt = DateTime.fromMillisecondsSinceEpoch(store.state.syncStore.lastAttempt ?? 0);

          // See if the last attempted sy nc is older than 60 seconds
          final isLastAttemptOld = DateTime.now().difference(lastAttempt).compareTo(Duration(seconds: 90));

          // syncing for the first time
          if (syncing && !synced) {
            return true;
          }

          // syncing for the first time since going offline
          if (syncing && offline) {
            return true;
          }

          // joining or removing a room
          if (loadingRooms) {
            return true;
          }

          // syncing for the first time in a while or restarting the app
          if (syncing && (0 < isLastAttemptOld || backgrounded)) {
            return true;
          }

          return false;
        }(),
        currentUser: store.state.authStore.user,
        roomTypeBadgesEnabled: store.state.settingsStore.roomTypeBadgesEnabled,
        chatSettings: store.state.settingsStore.chatSettings,
        onDebug: () async {
          debugPrint('[onDebug] trigged debug function @ home');
        },
        onMarkAllRead: () {
          store.dispatch(markRoomsReadAll());
        },
        onArchiveRoom: ({Room? room}) async {
          store.dispatch(archiveRoom(room: room));
        },
        onFetchSyncForced: () async {
          await store.dispatch(
            fetchSync(since: store.state.syncStore.lastSince),
          );
          return Future(() => true);
        },
        onLeaveChat: ({Room? room}) {
          return store.dispatch(leaveRoom(room: room));
        },
        onDeleteChat: ({Room? room}) {
          return store.dispatch(removeRoom(room: room));
        },
        onSelectHelp: () async {
          try {
            if (await canLaunch(Values.openHelpUrl)) {
              await launch(Values.openHelpUrl);
            } else {
              throw 'Could not launch ${Values.openHelpUrl}';
            }
          } catch (error) {}
        },
      );
}
