#NoTrayIcon

TCPStartup()
OnAutoItExitRegister(TCPShutdown)

Global $hSock = TCPConnect("127.0.0.1", 12345)
If $hSock > 0 Then
	_SendPkt("Salut la compagnie!")
	_SendPkt("Voici le 2e paquet.")
	_SendPkt("Je vais maintenant me déconnecter :(")
	_SendPkt("BYE") ; special packet (server will close)
EndIf
TCPCloseSocket($hSock)
Sleep(1000)

Func _SendPkt($sData)
	Local $bData = StringToBinary($sData, 4)
	Local $bPktLen = Binary(Int(BinaryLen($bData), 1))
	; ---
	TCPSend($hSock, $bPktLen) ; send packet len as 4 bytes int
	TCPSend($hSock, Binary($bData)) ; send packet data
EndFunc