#include-once
#include <Date.au3>

#cs
Simple, flexible, reusable, multi-clients TCP server

The MIT License (MIT)

Copyright (c) 2015 matwachich@gmail.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#ce

#cs
Functions :
_TCPSrv_Create
_TCPSrv_SetCallbacks
_TCPSrv_Destroy
_TCPSrv_PeerInfo
_TCPSrv_PeerRecvBufferSetLen
_TCPSrv_PeersCount
_TCPSrv_PeersArray
_TCPSrv_PeersCycle
_TCPSrv_PeersBroadcast
_TCPSrv_PeerKick
_TCPSrv_PeersKick
_TCPSrv_PeerExtGet
_TCPSrv_PeerExtSet
_TCPSrv_PeerExtGetMap
_TCPSrv_PeerExtSetMap
_TCPSrv_Process
#ce

; ===============================================================================================================================
; Internals

;~ Note on onReceive() callback :
;~ ------------------------------
;~ 	Each time a peer receives data, it is appended to the peer's internal data buffer.
;~ 	The onReceive() callback is called each time there is some data in the buffer.
;~ 	In the callback function, the user must use (consume) some/all data in the buffer.
;~ 	The user is not obliged to use all the data. So he must returns from the callback the amount of data he used (consumed) from the buffer,
;~   so that this data will be discarded and not passed on the next call.
;~	The user can return special values :
;~ 		0 => no data used
;~ 		-1 => all data has been used (same as BinaryLen($bData))
;~ 		a value > BinaryLen($bData) has the same effect as -1

Const Enum _                  ; server structure = map
	$__gSRV_SOCKET, _         ; [] = listen socket
	$__gSRV_MAXPEERS, _       ; [] = max peers
	$__gSRV_PEERMAXRECV, _    ; [] = peer max bytes for TCPRecv (will be copied to each peer's data)
	$__gSRV_IDLETIMEOUT, _    ; [] = max time without receiving data (-1 to no time out)
	$__gSRV_DICTPEERS, _      ; [] = map of peers > socket = map[ip, port, connTime, idleTimer, maxRecv, buffer, disconnectError]
	$__gSRV_DICTEXTDATA, _    ; [] = map of peers ext data > socket = map[]
	$__gSRV_PEERCYCLEDELAY, _ ; [] = peer cycle delay (-1 to deactivate)
	$__gSRV_PEERCYCLETIMER, _ ; [] = peer cycle timer
	$__gSRV_ONCONNECT, _      ; [] = onConnect   (ByRef $aServer, $iSocket)
	$__gSRV_ONDISCONNECT, _   ; [] = onDisconnect(ByRef $aServer, $iSocket, $bBufferContent, $sError)
	$__gSRV_ONRECEIVE, _      ; [] = onReceive   (ByRef $aServer, $iSocket, $bData) $iConsumedBytes
	$__gSRV_ONERROR, _        ; [] = onError     (ByRef $aServer, $iSocket, $sError)
	$__gSRV_ONPEERCYCLE, _    ; [] = onPeerCycle (ByRef $aServer, $iSocket)
	$__gSRV__MAX

Const Enum _
	$__gSRV_PEERDATA_IP, _
	$__gSRV_PEERDATA_PORT, _
	$__gSRV_PEERDATA_IPPORT, _
	$__gSRV_PEERDATA_CONNTIME, _
	$__gSRV_PEERDATA_IDLETIMER, _
	$__gSRV_PEERDATA_MAXRECV, _
	$__gSRV_PEERDATA_BUFFER, _
	$__gSRV_PEERDATA_DISCONNECTERROR

Const $__gSRV_hDllWinSock = DllOpen("Ws2_32.dll")

; ===============================================================================================================================
; Base functions

Func _TCPSrv_Create($sIp, $iPort, $iMaxPeers = -1, $iMaxRecvBytes = 4096, $iIdleTimeout = -1, $iPeerCycleDelay = -1)
	TCPStartup()
	; ---
	; maps that will hold peers and peers extended data
	Local $mMap1[], $mMap2[]
	; ---
	; main server map
	Local $aRet[]
	; ---
	; create listening socket
	$aRet[$__gSRV_SOCKET]         = TCPListen($sIp, $iPort)
	If $aRet[$__gSRV_SOCKET] <= 0 Then Return SetError(@error, @extended, Null)
	; ---
	; populate server map
	$aRet[$__gSRV_MAXPEERS]       = $iMaxPeers
	$aRet[$__gSRV_PEERMAXRECV]    = $iMaxRecvBytes
	$aRet[$__gSRV_IDLETIMEOUT]    = $iIdleTimeout
	$aRet[$__gSRV_DICTPEERS]      = $mMap1
	$aRet[$__gSRV_DICTEXTDATA]    = $mMap2
	$aRet[$__gSRV_PEERCYCLEDELAY] = $iPeerCycleDelay
	$aRet[$__gSRV_PEERCYCLETIMER] = TimerInit()
	$aRet[$__gSRV_ONCONNECT]      = Null
	$aRet[$__gSRV_ONDISCONNECT]   = Null
	$aRet[$__gSRV_ONRECEIVE]      = Null
	$aRet[$__gSRV_ONERROR]        = Null
	$aRet[$__gSRV_ONPEERCYCLE]    = Null
	; ---
	Return $aRet
EndFunc

Func _TCPSrv_SetCallbacks(ByRef $aServer, $hOnConnect = Null, $hOnDisconnect = Null, $hOnReceive = Null, $hOnError = Null, $hOnPeerCycle = Null)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	$aServer[$__gSRV_ONCONNECT]      = $hOnConnect
	$aServer[$__gSRV_ONDISCONNECT]   = $hOnDisconnect
	$aServer[$__gSRV_ONRECEIVE]      = $hOnReceive
	$aServer[$__gSRV_ONERROR]        = $hOnError
	$aServer[$__gSRV_ONPEERCYCLE]    = $hOnPeerCycle
	; ---
	Return True
EndFunc

Func _TCPSrv_Destroy(ByRef $aServer)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	; disconnect all peers
	_TCPSrv_PeersKick($aServer)
	_TCPSrv_Process($aServer) ; to call disconnect callbacks
	; ---
	; destroy server
	TCPCloseSocket($aServer[$__gSRV_SOCKET])
	$aServer = Null
	; ---
	TCPShutdown()
	Return True
EndFunc

; ===============================================================================================================================
; Peers functions

Func _TCPSrv_PeerInfo(ByRef $aServer, $hSock)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, Null)
	; ---
	Local $aRet[] = [ _
		$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_IP], _
		$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_PORT], _
		$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_IPPORT], _
		$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_CONNTIME], _
		TimerDiff($aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_IDLETIMER]), _
		$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_MAXRECV], _
		BinaryLen($aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_BUFFER]) _
	]
	Return $aRet
EndFunc

Func _TCPSrv_PeerRecvBufferSetLen(ByRef $aServer, $hSock, $iBuffLen = Default)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	If $iBuffLen = Default Then $iBuffLen = $aServer[$__gSRV_PEERMAXRECV]
	$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_MAXRECV] = $iBuffLen
	; ---
	Return True
EndFunc

Func _TCPSrv_PeersCount(ByRef $aServer)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, Null)
	; ---
	Return UBound($aServer[$__gSRV_DICTPEERS])
EndFunc

Func _TCPSrv_PeersArray(ByRef $aServer)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, Null)
	; ---
	Return MapKeys($aServer[$__gSRV_DICTPEERS])
EndFunc

Func _TCPSrv_PeersCycle(ByRef $aServer, $hProc, $vUserData = Null) ; $hProc(ByRef $aServer, $hSock, $vUserData = Null)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	If IsFunc($hProc) Then
		For $hSock In MapKeys($aServer[$__gSRV_DICTPEERS])
			$hProc($aServer, $hSock, $vUserData)
		Next
	EndIf
	; ---
	Return True
EndFunc

Func _TCPSrv_PeerSend(ByRef $aServer, $hSock, $bData)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_IDLETIMER] = TimerInit() ; reset idle timer
	; ---
	Return TCPSend($hSock, $bData) == BinaryLen($bData)
EndFunc

Func _TCPSrv_PeersBroadcast(ByRef $aServer, $bData)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	Local $ret = True, $iDataLen = BinaryLen($bData)
	For $hSock In MapKeys($aServer[$__gSRV_DICTPEERS])
		$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_IDLETIMER] = TimerInit() ; reset idle timer
		; ---
		$ret = (TCPSend($hSock, $bData) == $iDataLen)
	Next
	; ---
	Return $ret
EndFunc

Func _TCPSrv_PeerKick(ByRef $aServer, $hSock, $sError = Default)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	If $sError <> Default Then
		$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_DISCONNECTERROR] = String($sError)
	EndIf
	; ---
	Return TCPCloseSocket($hSock) == 1
EndFunc

Func _TCPSrv_PeersKick(ByRef $aServer, $sError = Default)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	For $hSock In $aServer[$__gSRV_DICTPEERS]
		If $sError <> Default Then
			$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_DISCONNECTERROR] = String($sError)
		EndIf
		TCPCloseSocket($hSock)
	Next
	; ---
	Return True
EndFunc

; ===============================================================================================================================
; Peers ext data functions

Func _TCPSrv_PeerExtGet(ByRef $aServer, $hSock, $sKey)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, Null)
	; ---
	Return $aServer[$__gSRV_DICTEXTDATA][$hSock][$sKey]
EndFunc

Func _TCPSrv_PeerExtSet(ByRef $aServer, $hSock, $sKey, $vValue)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	$aServer[$__gSRV_DICTEXTDATA][$hSock][$sKey] = $vValue
	; ---
	Return True
EndFunc

Func _TCPSrv_PeerExtGetMap(ByRef $aServer, $hSock)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, Null)
	; ---
	Return $aServer[$__gSRV_DICTEXTDATA][$hSock]
EndFunc

Func _TCPSrv_PeerExtSetMap(ByRef $aServer, $hSock, ByRef $hMap)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	$aServer[$__gSRV_DICTEXTDATA][$hSock] = $hMap
	; ---
	Return True
EndFunc

; ===============================================================================================================================
; Process functions

Func _TCPSrv_Process(ByRef $aServer)
	If Not __tcpSrv_isServerValid($aServer) Then Return SetError(-1, 0, False)
	; ---
	; accept new connections
	Local $hSock = TCPAccept($aServer[$__gSRV_SOCKET])
	If $hSock > 0 Then
		If $aServer[$__gSRV_MAXPEERS] <= 0 Or UBound($aServer[$__gSRV_DICTPEERS]) < $aServer[$__gSRV_MAXPEERS] Then
			; peer's remote address
			Local $aSockAddr = __tcpSrv_socketGetAddr($hSock)
			; ---
			; peer's data map
			Local $aPeer[]
			$aPeer[$__gSRV_PEERDATA_IP]              = $aSockAddr[0]
			$aPeer[$__gSRV_PEERDATA_PORT]            = $aSockAddr[1]
			$aPeer[$__gSRV_PEERDATA_IPPORT]          = $aSockAddr[0] & ":" & $aSockAddr[1]
			$aPeer[$__gSRV_PEERDATA_CONNTIME]        = _NowCalc()
			$aPeer[$__gSRV_PEERDATA_IDLETIMER]       = TimerInit()
			$aPeer[$__gSRV_PEERDATA_MAXRECV]         = $aServer[$__gSRV_PEERMAXRECV]
			$aPeer[$__gSRV_PEERDATA_BUFFER]          = Binary("")
			$aPeer[$__gSRV_PEERDATA_DISCONNECTERROR] = ""
			$aServer[$__gSRV_DICTPEERS][$hSock] = $aPeer
			; ---
			; peer's extended data map
			Local $aExtData[]
			$aServer[$__gSRV_DICTEXTDATA][$hSock] = $aExtData
			; ---
			If IsFunc($aServer[$__gSRV_ONCONNECT]) Then $aServer[$__gSRV_ONCONNECT]($aServer, $hSock)
		Else
			; server max peers reached
			TCPCloseSocket($hSock)
			If IsFunc($aServer[$__gSRV_ONERROR]) Then $aServer[$__gSRV_ONERROR]($aServer, $hSock, "Disconnected (maximum peers count reached)")
		EndIf
	EndIf
	; ---
	; check peer cycle delay
	Local $bPeerCycle = False
	If $aServer[$__gSRV_PEERCYCLEDELAY] > 0 And TimerDiff($aServer[$__gSRV_PEERCYCLETIMER]) >= $aServer[$__gSRV_PEERCYCLEDELAY] Then
		$aServer[$__gSRV_PEERCYCLETIMER] = TimerInit()
		$bPeerCycle = True
	EndIf
	; ---
	; loop on all connected sockets
	For $hSock In MapKeys($aServer[$__gSRV_DICTPEERS])
		If $bPeerCycle And IsFunc($aServer[$__gSRV_ONPEERCYCLE]) Then $aServer[$__gSRV_ONPEERCYCLE]($aServer, $hSock)
		; ---
		__tcpSrv_processRecv($aServer, $hSock)
		__tcpSrv_processIdleTimeout($aServer, $hSock)
	Next
	; ---
	Return True
EndFunc

; ---

Func __tcpSrv_processRecv(ByRef $aServer, $hSock)
	Local $bRecv = TCPRecv($hSock, $aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_MAXRECV], 1)
	If @error Then
		; set disconnect error message
		If Not $aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_DISCONNECTERROR] Then ; not set by _TCPSrv_Peer(s)Kick
			If @error = -1 Or @error = -2 Then
				$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_DISCONNECTERROR] = "@error " & @error
			Else
				$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_DISCONNECTERROR] = "WSAError " & @error
			EndIf
		EndIf
		; ---
		; callback
		If IsFunc($aServer[$__gSRV_ONDISCONNECT]) Then
			$aServer[$__gSRV_ONDISCONNECT]( _
				$aServer, _
				$hSock, _
				$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_BUFFER], _
				$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_DISCONNECTERROR] _
			)
		EndIf
		; ---
		; clean maps
		MapRemove($aServer[$__gSRV_DICTPEERS], $hSock)
		MapRemove($aServer[$__gSRV_DICTEXTDATA], $hSock)
		; ---
		TCPCloseSocket($hSock) ; is it really usefull?
	ElseIf $bRecv Or $aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_BUFFER] Then
		; append to receive buffer
		If $bRecv Then $aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_BUFFER] &= Binary($bRecv)
		Local $iBuffLen = BinaryLen($aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_BUFFER])
		; ---
		; callback
		Local $iConsumedBytes = $iBuffLen
		If IsFunc($aServer[$__gSRV_ONRECEIVE]) Then
			$iConsumedBytes = $aServer[$__gSRV_ONRECEIVE]($aServer, $hSock, $aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_BUFFER])
			If $iConsumedBytes < 0 Then $iConsumedBytes = $iBuffLen
		EndIf
		; ---
		; remove consumed bytes from buffer
		If $iConsumedBytes > 0 And $iConsumedBytes < $iBuffLen Then
			$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_BUFFER] = BinaryMid($aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_BUFFER], $iConsumedBytes)
		ElseIf $iConsumedBytes >= $iBuffLen Then
			; all bytes consumed => empty buffer
			$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_BUFFER] = Binary("")
		EndIf
		; ---
		$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_IDLETIMER] = TimerInit() ; reset idle timer
	EndIf
EndFunc

Func __tcpSrv_processIdleTimeout(ByRef $aServer, $hSock)
	If $aServer[$__gSRV_IDLETIMEOUT] > 0 And TimerDiff($aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_IDLETIMER]) > $aServer[$__gSRV_IDLETIMEOUT] Then
		TCPCloseSocket($hSock)
		$aServer[$__gSRV_DICTPEERS][$hSock][$__gSRV_PEERDATA_DISCONNECTERROR] = "Idle (timed-out)"
	EndIf
EndFunc

; ===============================================================================================================================
; Helpers (internal)

Func __tcpSrv_isServerValid(ByRef $aServer)
	Return UBound($aServer) = $__gSRV__MAX
EndFunc

Func __tcpSrv_socketGetAddr($hSock)
	Local $aRet[] = ["", -1] ; ip, port
	; ---
	Local $tSockAddr = DllStructCreate("short;ushort;uint;char[8]")
	Local $ret = DllCall($__gSRV_hDllWinSock, "int", "getpeername", "int", $hSock, "struct*", $tSockAddr, "int*", DllStructGetSize($tSockAddr))
	If @error Then SetError(1, 0, $aRet)
	; ---
	$ret = DllCall($__gSRV_hDllWinSock, "str", "inet_ntoa", "int", DllStructGetData($tSockAddr, 3))
	If Not @error Then $aRet[0] = $ret[0]
	$aRet[1] = DllStructGetData($tSockAddr, 2)
	; ---
	Return $aRet
EndFunc
