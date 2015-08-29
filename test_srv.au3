#NoTrayIcon
#include "tcpserver.au3"

Opt("TCPTimeOut", 0)
$aSrv = _TCPSrv_Create("0.0.0.0", 12345)
_TCPSrv_SetCallbacks($aSrv, _onConnect, _onDisconnect, _onReceive, _onError)

While 1
	_TCPSrv_Process($aSrv)
	Sleep(100)
WEnd

_TCPSrv_Destroy($aSrv)

; ===============================================================================================================================

Func _onConnect(ByRef $aSrv, $hSock)
	ConsoleWrite("New peer : " & $hSock & " (" & _TCPSrv_PeerInfo($aSrv, $hSock)[2] & ")" & @CRLF)
	; ---
	TCPSend($hSock, StringToBinary('<pkt>Salut la compagnie!</pkt>', 4))
	TCPSend($hSock, StringToBinary('<pkt>Bienvenu sur le serveur!</pkt>', 4))
EndFunc

Func _onDisconnect(ByRef $aSrv, $hSock, $bBufferContent, $sError)
	ConsoleWrite("Lost peer : " & $hSock & " (" & $sError & ")" & (($bBufferContent) ? (" - " & BinaryLen($bBufferContent) & " byte(s) lost") : ("")) & @CRLF)
EndFunc

Func _onReceive(ByRef $aSrv, $hSock, $bData)
	$bData = BinaryToString($bData, 4)
	Local $aReg = StringRegExp($bData, '<pkt>(.+?)</pkt>', 3)
	If IsArray($aReg) Then
		$sMsg = $aReg[0]
		ConsoleWrite("Recv (" & _TCPSrv_PeerInfo($aSrv, $hSock)[2] & ") : " & $sMsg & @CRLF)
		; ---
		_TCPSrv_PeersBroadcast($aSrv, StringToBinary('<pkt>' & $sMsg & '</pkt>', 4))
		; ---
		Return BinaryLen(StringToBinary($sMsg, 4)) + 5 + 6
	Else
		Return 0 ; do not consume any data
	EndIf
EndFunc

Func _onError(ByRef $aSrv, $hSock, $sError)
	ConsoleWrite("! Error: " & $sError & @CRLF)
EndFunc

;~ Func _onPeerCycle(ByRef $aSrv, $hSock)
;~ EndFunc
