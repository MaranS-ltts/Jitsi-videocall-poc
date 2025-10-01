import 'package:flutter/material.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'dart:async';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:video_call_poc/datamodels/chat_message.dart';
import 'package:video_call_poc/datamodels/message_dto.dart';

class ChatPage extends StatefulWidget {
  final String username;
  const ChatPage({Key? key, required this.username}) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  // --- Controllers, Services, and State Variables ------
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final JitsiMeet _jitsiMeet = JitsiMeet();
  HubConnection? _hubConnection;

  late String _myUsername;
  bool _isConnectionFailed = false;
  bool _isConnected = false;
  bool _isJoined = false;
  List<String> _onlineUsers = [];
  String? _currentChatPartner;
  final Map<String, List<ChatMessage>> _chatHistories = {};
  String? _outgoingCallRoom;
  Timer? _outgoingCallTimer;

  @override
  void initState() {
    super.initState();
    _myUsername = widget.username;
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(milliseconds: 100), _connectAndJoin);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _connectAndJoin();
  }

  @override
  void dispose() {
    _hubConnection?.stop();
    _messageController.dispose();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: _currentChatPartner == null ? _buildUserList() : _buildChatView(),
      backgroundColor: Colors.grey[100],
    );
  }

  // --- SignalR Connection & Handlers ---

  void _connectAndJoin() async {
    // String SERVER_URL =
    //     'http://websocket.shantecharch.co.in/jitsi/signalr?username=$_myUsername';

    String SERVER_URL = 'http://192.168.14.10:5002/jitsi/signalr?username=$_myUsername';
    // Check connection is alive, disconnect before re-connect
    if (_hubConnection != null &&
        _hubConnection!.state == HubConnectionState.Connected) {
      await _hubConnection?.stop();
      _hubConnection = null;
    }

    Future.delayed(const Duration(milliseconds: 500), () async {
      _hubConnection = HubConnectionBuilder()
          .withUrl(SERVER_URL, transportType: HttpTransportType.LongPolling)
          // .withAutomaticReconnect()
          .build();

      _hubConnection?.onclose(({error}) {
        print("Connection closed: ${error?.toString()}");
        _setStateIfMounted(() => _isConnected = false);
      });

      _hubConnection?.on('UserConnected', _handleUserConnected);
      _hubConnection?.on('GetAllUser', _handleUpdateUserList);
      _hubConnection?.on('ReceiveMessage', _handleReceiveMessage);

      await _hubConnection
          ?.start()
          ?.then((_) => _setStateIfMounted(() => _isConnected = true))
          .catchError((e) {
        print('Connection failed: $e');
        _setStateIfMounted(() => _isConnectionFailed = true);
      });
    });

    _hubConnection?.onreconnecting(({error}) {
      print("Reconnecting… ${error?.toString()}");
    });

    _hubConnection?.onreconnected(({connectionId}) {
      print("Reconnected with id: $connectionId");
    });
  }

  void _handleUserConnected(List<Object?>? args) {
    if (args != null && args.isNotEmpty && args[0] == _myUsername) {
      _setStateIfMounted(() => _isJoined = true);
    }
  }

  void _handleUpdateUserList(List<Object?>? args) {
    print(args);
    if (args != null && args.isNotEmpty) {
      final users = (args[0] as List)
          .map((item) => item.toString())
          .where((name) => name != _myUsername)
          .toList();
      _setStateIfMounted(() => _onlineUsers = users);
    }
  }

  void _handleReceiveMessage(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    try {
      final dto = MessageDto.fromJson(args[0] as Map<String, dynamic>);
      print(
          'Received command "${dto.message}" from sender "${dto.sender}" for receiver "${dto.receiver}"');

      if (dto.receiver != _myUsername) return;

      switch (dto.message) {
        case 'initiateCall':
          _handleIncomingCall(dto.sender, dto.roomName);
          break;
        case 'accept':
          _handleCallAccepted(dto.roomName);
          break;
        case 'decline':
          _handleCallDeclined(dto.roomName);
        case 'EndCall':
          _handleEndCall("Missed call from ${dto.sender}");
          break;
        default:
          final newMessage = ChatMessage(
              sender: dto.sender,
              recipient: _myUsername,
              message: dto.message,
              isMe: false);
          _setStateIfMounted(() {
            _chatHistories.putIfAbsent(dto.sender, () => []).add(newMessage);
          });
          if (dto.sender == _currentChatPartner) _scrollToBottom();
          break;
      }
    } catch (e) {
      print('Could not parse received DTO: $e');
    }
  }

  // --- Call State Handlers ---

  void _handleIncomingCall(String caller, String room) {
    _showIncomingCallDialog(caller, room);
  }

  void _handleCallAccepted(String roomName) {
    if (mounted && _outgoingCallRoom == roomName) {
      _outgoingCallTimer?.cancel();
      Navigator.of(context).pop();
      _joinJitsiMeeting(roomName);
      _setStateIfMounted(() => _outgoingCallRoom = null);
    }
  }

  void _handleCallDeclined(String message) {
    if (mounted && _outgoingCallRoom != null) {
      _outgoingCallTimer?.cancel();
      Navigator.of(context).pop();
      _showErrorSnackBar(message);
      _setStateIfMounted(() => _outgoingCallRoom = null);
    }
  }
  void _handleEndCall(String message) {
    if (mounted) {
      Navigator.of(context).pop();
      _showErrorSnackBar(message);
    }
  }

  // --- UI Interaction & Business Logic ---

  void _initiateCall(String callee) {
    final roomName =
        'cl_support_call_${_myUsername}_${callee}_${DateTime.now().millisecondsSinceEpoch}';
    _setStateIfMounted(() => _outgoingCallRoom = roomName);
    _showOutgoingCallDialog(callee, roomName);

    final callDto = MessageDto(
      receiver: callee, // CORRECTED ORDER
      sender: _myUsername,
      message: 'initiateCall',
      roomName: roomName,
    );
    _hubConnection
        ?.invoke('SendMessageToUser', args: <Object>[callDto.toJson()]);
    _outgoingCallTimer?.cancel();
    _outgoingCallTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _outgoingCallRoom == roomName) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        final endCallDto = MessageDto(
            receiver: callee,
            sender: _myUsername,
            message: 'EndCall',
            roomName: roomName);
        _hubConnection
            ?.invoke('SendMessageToUser', args: <Object>[endCallDto.toJson()]);
        _showErrorSnackBar('$callee is not answering the call.');
        _setStateIfMounted(() => _outgoingCallRoom = null);
      }
    });
  }

  void _sendMessage() {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || !_isJoined || _currentChatPartner == null)
      return;

    final messageDto = MessageDto(
      receiver: _currentChatPartner!, // CORRECTED ORDER
      sender: _myUsername,
      message: messageText,
      roomName: "chat",
    );
    _hubConnection!
        .invoke('SendMessageToUser', args: <Object>[messageDto.toJson()]);

    final newMessage = ChatMessage(
        sender: _myUsername,
        recipient: _currentChatPartner!,
        message: messageText,
        isMe: true);
    _setStateIfMounted(() {
      _chatHistories
          .putIfAbsent(_currentChatPartner!, () => [])
          .add(newMessage);
    });
    _scrollToBottom();
    _messageController.clear();
  }

  void _joinJitsiMeeting(String roomName) {
    var options = JitsiMeetConferenceOptions(
      serverURL: "https://jitsi.shantecharch.co.in",
      room: roomName,
      configOverrides: {
        "startWithAudioMuted": false,
        "startWithVideoMuted": false,
        "subject": "CurrentLighting Support",
      },
      userInfo: JitsiMeetUserInfo(
          displayName: _myUsername, email: "$_myUsername@example.com"),
    );
    _jitsiMeet.join(options);
    JitsiMeetEventListener(
      conferenceJoined: (eventName){
        print("conference joined: $eventName");
      },
      conferenceTerminated: (eventName, data) {
        print("Conference terminated: $eventName, $data");
        // Example: Navigator.pop(context);
      },
    );
  }

  // --- Dialogs & UI Helpers ---

  void _showOutgoingCallDialog(String callee, String room) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Calling...'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Calling $callee'),
          ]),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                _outgoingCallTimer?.cancel();
                final cancelDto = MessageDto(
                    receiver: callee,
                    sender: _myUsername,
                    message: 'EndCall',
                    roomName: room);
                _hubConnection?.invoke('SendMessageToUser',
                    args: <Object>[cancelDto.toJson()]);
                Navigator.of(context).pop();
                _setStateIfMounted(() => _outgoingCallRoom = null);
              },
            ),
          ],
        );
      },
    );
  }

  void _showIncomingCallDialog(String caller, String room) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Incoming Call'),
          content: Text('$caller is calling you.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Decline'),
              onPressed: () {
                final declineDto = MessageDto(
                  receiver: caller, // CORRECTED ORDER
                  sender: _myUsername,
                  message: 'decline',
                  roomName: room,
                );
                _hubConnection?.invoke('SendMessageToUser',
                    args: <Object>[declineDto.toJson()]);
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Accept'),
              onPressed: () {
                final acceptDto = MessageDto(
                  receiver: caller, // CORRECTED ORDER
                  sender: _myUsername,
                  message: 'accept',
                  roomName: room,
                );
                _hubConnection?.invoke('SendMessageToUser',
                    args: <Object>[acceptDto.toJson()]);
                Navigator.of(context).pop();
                _joinJitsiMeeting(room);
              },
            ),
          ],
        );
      },
    );
  }

  // --- Other UI methods ---
  void _selectChatPartner(String? username) {
    _setStateIfMounted(() => _currentChatPartner = username);
    if (username != null) _scrollToBottom(immediately: true);
  }

  void _setStateIfMounted(void Function() fn) {
    if (mounted) setState(fn);
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
      ));
    }
  }

  void _scrollToBottom({bool immediately = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (immediately) {
        _scrollController.jumpTo(maxScroll);
      } else {
        _scrollController.animateTo(maxScroll,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  AppBar _buildAppBar() {
    bool isChatting = _currentChatPartner != null;
    return AppBar(
      leading: isChatting
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _selectChatPartner(null))
          : null,
      title: Text(
        isChatting
            ? 'Chat with $_currentChatPartner'
            : 'CurrentLighting Support',
        style: TextStyle(fontSize: 16),
      ),
      actions: [
        if (isChatting)
          IconButton(
              icon: const Icon(Icons.video_call),
              onPressed: () => _initiateCall(_currentChatPartner!)),
        IconButton(
            onPressed: () {
              _setStateIfMounted(() {
                _isConnected = false;
                _isJoined = false;
                _isConnectionFailed = false;
              });
              _connectAndJoin();
            },
            icon: const Icon(Icons.refresh_rounded)),
        Padding(
          padding: const EdgeInsets.only(left: 6, right: 16.0),
          child: Tooltip(
            message: _isJoined
                ? 'Joined as $_myUsername'
                : (_isConnected ? 'Connecting...' : 'Disconnected'),
            child: Icon(
              _isJoined
                  ? Icons.cloud_done
                  : (_isConnected ? Icons.cloud_queue : Icons.cloud_off),
              color: _isJoined
                  ? Colors.greenAccent[400]
                  : (_isConnected ? Colors.orangeAccent : Colors.black87),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(_myUsername,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            accountEmail: Text(_isJoined ? 'Online' : 'Offline'),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              child: Text(
                  _myUsername.isNotEmpty ? _myUsername[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 30.0, color: Colors.white)),
            ),
            decoration:
                BoxDecoration(color: Theme.of(context).primaryColorDark),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    if (!_isJoined) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _isConnectionFailed ? const SizedBox() : CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
              _isConnected
                  ? 'Joining to support...'
                  : _isConnectionFailed
                      ? 'Connection failed! someting went wrong.'
                      : 'Connecting to support...',
              style: TextStyle(fontSize: 16, color: Colors.grey[600])),
        ]),
      );
    }
    if (_onlineUsers.isEmpty) {
      return const Center(
          child: Text('No other users are currently online.',
              style: TextStyle(fontSize: 16, color: Colors.grey)));
    }
    return ListView.separated(
      itemCount: _onlineUsers.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = _onlineUsers[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
          title:
              Text(user, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: const Text('Online'),
          onTap: () => _selectChatPartner(user),
          trailing: const Icon(Icons.chevron_right),
        );
      },
    );
  }

  Widget _buildChatView() {
    final List<ChatMessage> currentMessages =
        _chatHistories[_currentChatPartner!] ?? [];
    return Column(
      children: [
        Expanded(
          child: currentMessages.isEmpty
              ? Center(
                  child: Text('Say hello to $_currentChatPartner!',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600])))
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: currentMessages.length,
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  itemBuilder: (context, index) =>
                      _buildMessageBubble(currentMessages[index]),
                ),
        ),
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final radius = const Radius.circular(16.0);
    final borderRadius = BorderRadius.only(
      topLeft: radius,
      topRight: radius,
      bottomLeft: msg.isMe ? radius : Radius.zero,
      bottomRight: msg.isMe ? Radius.zero : radius,
    );
    final color = msg.isMe ? Theme.of(context).primaryColor : Colors.grey[600];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 10.0),
      child: Row(
        mainAxisAlignment:
            msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
              decoration:
                  BoxDecoration(color: color, borderRadius: borderRadius),
              child: Text(msg.message,
                  style: const TextStyle(fontSize: 16.0, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 5,
            offset: const Offset(0, -2)),
      ]),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Message $_currentChatPartner...',
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25.0),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 10.0),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          Material(
            color: Theme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(25.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(25.0),
              onTap: _sendMessage,
              child: const Padding(
                padding: EdgeInsets.all(10.0),
                child:
                    Icon(Icons.send_rounded, color: Colors.white, size: 24.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
