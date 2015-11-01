# AutoIt3 Generic TCP Server
With this UDF, making a simple and flexible multi-client TCP server in your scripts is really easy! You can also create multiple TCP servers in a script.

This UDF requires AutoIt beta 3.3.15.0, because it extensively uses the new map feature of the language.

# Server creation and configuration
- `_TCPSrv_Create`: create a TCP server.
    - $sIp, $iPort : listening address (see TCPListen documentation)
    - $iMaxPeers (default = -1 : no limit) : maximum peers that the server will accept
    - $iMaxRecvBytes (default = 4096) : maximum bytes that TCPRecv will accept. This value can be modified for each pear separately (`_TCPSrv_PeerRecvBufferSetLen`).
    - $iIdleTimeout (default = 0 : no timeout) : maximum time (in ms) without receiveing any data from a peer before it gets kicked.
    - $iPeerCycleDelay (default = 0 : no cycle) :
- `_TCPSrv_SetCallbacks`: register callback functions for a TCP server.
- `_TCPSrv_Destroy`: destroy a TCP server. This function will disconnect all connected peers and call `_TCPSrv_Process` one time in order to fire onDisconnect callback.

# Callbacks
This UDF is event driven: you create a server and you register callback functions that will be called each time some event happens.

- `onConnect   (ByRef $aServer, $iSocket)`: called when a new peer ($iSocket) connects to $aServer.
- `onDisconnect(ByRef $aServer, $iSocket, $bBufferContent, $sError)`: called when a peer ($iSocket) disconnects from $aServer. $bBufferContent will contain peer's buffer content when disconnect occures (if any). $sError will be passed some error message (can be set by the $sError of _TCPSrv_Peer[s]Kick).
- `onReceive   (ByRef $aServer, $iSocket, $bData) = $iConsumedBytes`: called when a peer ($iSocket) receives some data ($bData). This callback must return the number of bytes ($iConsumedBytes) that must be discarded from the internal receive buffer (see remarks).
- `onError     (ByRef $aServer, $iSocket, $sError)`: called when an error occures.
- `onPeerCycle (ByRef $aServer, $iSocket)`: called every $iPeerCycleDelay (see _TCPSrv_Create) for every currently connected peer.

## Remark about onReceive callback
Each time a peer receives data, it is appended to the peer's internal data buffer. The onReceive() callback is called each time there is some data in the buffer.

In the callback function, the user must use (consume) some/all data in the buffer. The user is not obliged to use all the data. So he must returns from the callback the amount of data he used (consumed) from the buffer, so this data will be discarded and not passed on the next call.

The user can return special values :
- 0 => no data used
- -1 => all data has been used (same as BinaryLen($bData))
- a value > BinaryLen($bData) has the same effect as -1

# Peers management
- `_TCPSrv_PeerInfo`: get peer info as an array with the following values: IP adress, Port number, IP:Port, Connect time, Time (in ms) since last send/receive, Peer's max receive, Data size in peer's buffer.
- `_TCPSrv_PeerRecvBufferSetLen`: set peer's max receive (TCPRecv's second parameter).
- `_TCPSrv_PeersCount`: get connected peers count.
- `_TCPSrv_PeersArray`: get connected peers handles (sockets).
- `_TCPSrv_PeersCycle`: cycle through every connected peers. $hProc is called for every peer with the parameters $aServer, $iSock and $vUserData.
- `_TCPSrv_PeerSend`: send data to a peer.
- `_TCPSrv_PeersBroadcast`: broadcast data to all peers.
- `_TCPSrv_PeerKick`: kicks a peer. Optionnaly set an error message ($sError) that will be passed to onDisconnect callback.
- `_TCPSrv_PeersKick`: same as above, but for all peers.

# Peers extended data
Each connected peer has a Map were are stored user data.

- `_TCPSrv_PeerExtGet`
- `_TCPSrv_PeerExtSet`
- `_TCPSrv_PeerExtGetMap`
- `_TCPSrv_PeerExtSetMap`

# The Process function
- `_TCPSrv_Process`: this function must be called in your script's main loop so your server will work correctly. It is also responsible for calling the callbacks.