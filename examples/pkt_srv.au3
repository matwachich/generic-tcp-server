#NoTrayIcon
#include "..\tcpserver.au3"

#cs
in this example, data is transfered as packets : the packet len is transfered first (as a 4 bytes int) then the packet data
#ce

Const $iSizeOfInt = 4 ; bytes

Global $iRun = True

; start and configure the server
Global $aServer = _TCPSrv_Create("0.0.0.0", 12345, -1, $iSizeOfInt)
_TCPSrv_SetCallbacks($aServer, _onConnect, _onDisconnect, _onReceive, _onError)

; main loop
While $iRun
	_TCPSrv_Process($aServer)
	Sleep(100)
WEnd

_TCPSrv_Destroy($aServer)

; ===============================================================================================================================

Func _onConnect(ByRef $aServer, $hSock)
	ConsoleWrite("New peer : " & $hSock & " (" & _TCPSrv_PeerInfo($aServer, $hSock)[2] & ")" & @CRLF)
	; ---
	; init peer's extended data
	_TCPSrv_PeerExtSet($aServer, $hSock, "pkt_len", -1) ; currently receiving packet len. -1 for no packet being received => awaiting packet len
EndFunc

Func _onDisconnect(ByRef $aServer, $hSock, $bBufferContent, $sError)
	ConsoleWrite("Lost peer : " & $hSock & " (" & $sError & ")" & (($bBufferContent) ? (" - " & BinaryLen($bBufferContent) & " byte(s) lost") : ("")) & @CRLF)
EndFunc

Func _onReceive(ByRef $aServer, $hSock, $bData)
	Local $iPktLen = _TCPSrv_PeerExtGet($aServer, $hSock, "pkt_len")
	If $iPktLen = -1 Then
		If BinaryLen($bData) >= $iSizeOfInt Then ; do we have enough data (4 bytes)?
			$iPktLen = Int(BinaryMid($bData, 1, $iSizeOfInt), 1) ; extract packet size from 4 first bytes of received data
			_TCPSrv_PeerExtSet($aServer, $hSock, "pkt_len", $iPktLen) ; store incoming packet size in peer's extended data
			_TCPSrv_PeerRecvBufferSetLen($aServer, $hSock, $iPktLen) ; set the buffer big enough to receive the packet (TODO should set a limit to packet size here)
			Return $iSizeOfInt ; consume only packet size
		EndIf
	Else
		If BinaryLen($bData) >= $iPktLen Then ; is packet completly received?
			; packet received! extract data
			Local $bPkt = BinaryMid($bData, 1, $iPktLen)
			; ---
			; display pkt content
			ConsoleWrite("Recv " & $iPktLen & " byte(s) : " & BinaryToString($bPkt, 4) & @CRLF)
			; ---
			; check exit packet
			If BinaryToString($bPkt, 4) = "BYE" Then $iRun = False
			; ---
			; reset peer's state to "waiting packet size"
			_TCPSrv_PeerExtSet($aServer, $hSock, "pkt_len", -1)
			_TCPSrv_PeerRecvBufferSetLen($aServer, $hSock, $iSizeOfInt)
			Return $iPktLen ; consume packet size
		EndIf
	EndIf
EndFunc

Func _onError(ByRef $aServer, $hSock, $sError)
EndFunc
