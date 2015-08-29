#NoTrayIcon
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Compression=4
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

#include <ButtonConstants.au3>
#include <EditConstants.au3>
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>

#include <Date.au3>

TCPStartup()

Global $hSock = -1
Global $iConnTimer = TimerInit() + 5000

Global $sBuffer = ""

#Region ### START Koda GUI section ###
$hGUI = GUICreate("Chat", 434, 314, -1, -1)
	GUISetFont(10, 400, 0, "Consolas")
$Input = GUICtrlCreateInput("", 8, 280, 337, 23)
$B_Send = GUICtrlCreateButton("Send", 352, 280, 75, 25)
$Edit = GUICtrlCreateEdit("", 8, 8, 417, 265, BitOR($GUI_SS_DEFAULT_EDIT,$ES_READONLY))
GUISetState(@SW_SHOW)
#EndRegion ### END Koda GUI section ###

While 1
	$nMsg = GUIGetMsg()
	Switch $nMsg
		Case $GUI_EVENT_CLOSE
			ExitLoop
		Case $B_Send
			$sRead = GUICtrlRead($Input)
			If $hSock > 0 And $sRead Then
				TCPSend($hSock, StringToBinary('<pkt>' & $sRead & '</pkt>', 4))
				GUICtrlSetData($Input, "")
			EndIf
	EndSwitch
	; ---
	If $hSock <= 0 And TimerDiff($iConnTimer) >= 5000 Then
		Opt("TCPTimeOut", 5000)
		$hSock = TCPConnect("127.0.0.1", 12345)
		Opt("TCPTimeOut", 0)
		; ---
		If $hSock > 0 Then
			_Log("Connected!")
		EndIf
		; ---
		$iConnTimer = TimerInit()
	EndIf
	; ---
	If $hSock > 0 Then
		$bRecv = TCPRecv($hSock, 1024, 1)
		If @error Then
			$hSock = -1
			_Log("Disconnected!")
		EndIf
		If $bRecv Then $sBuffer &= BinaryToString($bRecv, 4)
	EndIf
	; ---
	If $sBuffer Then
		$aReg = StringRegExp($sBuffer, '<pkt>(.+?)</pkt>', 3)
		If IsArray($aReg) Then
			$sPkt = $aReg[0]
			$sBuffer = StringReplace($sBuffer, '<pkt>' & $sPkt & '</pkt>', '')
			; ---
			_Log($sPkt)
		EndIf
	EndIf
WEnd

TCPCloseSocket($hSock)
TCPShutdown()

; ===============================================================================================================================

Func _Log($sText)
	Local $sRead = GUICtrlRead($Edit)
	If $sRead Then
		GUICtrlSetData($Edit, $sRead & @CRLF & "[" & _NowTime() & "] " & $sText)
	Else
		GUICtrlSetData($Edit, "[" & _NowTime() & "] " & $sText)
	EndIf
EndFunc
