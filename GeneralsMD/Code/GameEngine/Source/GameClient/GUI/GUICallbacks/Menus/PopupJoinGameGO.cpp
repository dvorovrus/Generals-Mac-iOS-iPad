/*
**	Command & Conquer Generals Zero Hour(tm)
**	Copyright 2025 Electronic Arts Inc.
**
**	This program is free software: you can redistribute it and/or modify
**	it under the terms of the GNU General Public License as published by
**	the Free Software Foundation, either version 3 of the License, or
**	(at your option) any later version.
**
**	This program is distributed in the hope that it will be useful,
**	but WITHOUT ANY WARRANTY; without even the implied warranty of
**	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
**	GNU General Public License for more details.
**
**	You should have received a copy of the GNU General Public License
**	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

////////////////////////////////////////////////////////////////////////////////
//																																						//
//  (c) 2001-2003 Electronic Arts Inc.																				//
//																																						//
////////////////////////////////////////////////////////////////////////////////

// FILE: PopupJoinGame.cpp /////////////////////////////////////////////////
//-----------------------------------------------------------------------------
//
//                       Electronic Arts Pacific.
//
//                       Confidential Information
//                Copyright (C) 2002 - All Rights Reserved
//
//-----------------------------------------------------------------------------
//
//	created:	Jul 2002
//
//	Filename: 	PopupJoinGame.cpp
//
//	author:		Matthew D. Campbell
//
//	purpose:	Contains the Callbacks for the Join Game Popup
//
//-----------------------------------------------------------------------------
///////////////////////////////////////////////////////////////////////////////

//-----------------------------------------------------------------------------
// SYSTEM INCLUDES ////////////////////////////////////////////////////////////
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// USER INCLUDES //////////////////////////////////////////////////////////////
//-----------------------------------------------------------------------------
#include "PreRTS.h"	// This must go first in EVERY cpp file in the GameEngine

#include "Common/GlobalData.h"
#include "Common/NameKeyGenerator.h"
#include "GameClient/WindowLayout.h"
#include "GameClient/Gadget.h"
#include "GameClient/KeyDefs.h"
#include "GameClient/GadgetTextEntry.h"
#include "GameClient/GadgetStaticText.h"
#include "GameClient/GadgetPushButton.h"
#include "GameNetwork/GameSpy/PeerDefs.h"
#include "GameNetwork/GameSpy/PeerThread.h"
#include "GameNetwork/GameSpyOverlay.h"
#include "GameNetwork/GeneralsOnline/NGMP_include.h"
#include "GameNetwork/GeneralsOnline/NGMP_interfaces.h"


//-----------------------------------------------------------------------------
// DEFINES ////////////////////////////////////////////////////////////////////
//-----------------------------------------------------------------------------

static NameKeyType parentPopupID = NAMEKEY_INVALID;
static NameKeyType textEntryGamePasswordID = NAMEKEY_INVALID;
static NameKeyType buttonCancelID = NAMEKEY_INVALID;
static NameKeyType buttonJoinID = NAMEKEY_INVALID;

static GameWindow *parentPopup = nullptr;
static GameWindow *textEntryGamePassword = nullptr;
static GameWindow *buttonJoin = nullptr;

static void joinGame( AsciiString password );
static void submitPassword();

//-----------------------------------------------------------------------------
// PUBLIC FUNCTIONS ///////////////////////////////////////////////////////////
//-----------------------------------------------------------------------------

//-------------------------------------------------------------------------------------------------
/** Initialize the PopupHostGameInit menu */
//-------------------------------------------------------------------------------------------------
void PopupJoinGameInit( WindowLayout *layout, void *userData )
{
	parentPopupID = TheNameKeyGenerator->nameToKey("PopupJoinGame.wnd:ParentJoinPopUp");
	parentPopup = TheWindowManager->winGetWindowFromId(nullptr, parentPopupID);

	textEntryGamePasswordID = TheNameKeyGenerator->nameToKey("PopupJoinGame.wnd:TextEntryGamePassword");
	textEntryGamePassword = TheWindowManager->winGetWindowFromId(parentPopup, textEntryGamePasswordID);
	GadgetTextEntrySetText(textEntryGamePassword, UnicodeString::TheEmptyString);

	NameKeyType staticTextGameNameID = TheNameKeyGenerator->nameToKey("PopupJoinGame.wnd:StaticTextGameName");
	GameWindow *staticTextGameName = TheWindowManager->winGetWindowFromId(parentPopup, staticTextGameNameID);
	GadgetStaticTextSetText(staticTextGameName, UnicodeString::TheEmptyString);

	buttonCancelID = NAMEKEY("PopupJoinGame.wnd:ButtonCancel");
	buttonJoinID = NAMEKEY("PopupJoinGame.wnd:ButtonJoin");

	// The stock password popup has only Cancel and relies on pressing Enter in
	// the text field. That is not discoverable on touch devices, so add an
	// explicit Join button beside Cancel at runtime.
	GameWindow *buttonCancel = TheWindowManager->winGetWindowFromId(parentPopup, buttonCancelID);
	if (parentPopup != nullptr)
	{
		Int joinX = 8;
		Int joinY = 8;
		Int joinWidth = 120;
		Int joinHeight = 30;
		GameFont *joinFont = nullptr;
		Int parentWidth = 0;
		Int parentHeight = 0;
		parentPopup->winGetSize(&parentWidth, &parentHeight);
		if (buttonCancel != nullptr)
		{
			Int cancelX = 0;
			Int cancelY = 0;
			buttonCancel->winGetPosition(&cancelX, &cancelY);
			buttonCancel->winGetSize(&joinWidth, &joinHeight);
			joinFont = buttonCancel->winGetFont();

			if (cancelX >= joinWidth + 16)
			{
				joinX = cancelX - joinWidth - 8;
				joinY = cancelY;
			}
			else if (cancelX + (joinWidth * 2) + 8 <= parentWidth)
			{
				joinX = cancelX + joinWidth + 8;
				joinY = cancelY;
			}
			else
			{
				joinX = cancelX;
				joinY = cancelY >= joinHeight + 16 ? cancelY - joinHeight - 8 : 8;
			}
		}
		else
		{
			joinX = (parentWidth - joinWidth) / 2;
			joinY = parentHeight - joinHeight - 12;
		}

		WinInstanceData joinInstData;
		joinInstData.init();
		joinInstData.m_id = buttonJoinID;
		BitSet(joinInstData.m_style, GWS_PUSH_BUTTON | GWS_MOUSE_TRACK);
		buttonJoin = TheWindowManager->gogoGadgetPushButton(parentPopup,
			WIN_STATUS_ENABLED, joinX, joinY, joinWidth, joinHeight,
			&joinInstData, joinFont, TRUE);
		if (buttonJoin != nullptr)
		{
			GadgetButtonSetText(buttonJoin, UnicodeString(L"Join"));
			NetworkLog(ELogVerbosity::LOG_RELEASE, "[NGMP-PASSWORD] Added explicit Join button to password popup");
		}
	}

	NGMP_OnlineServices_LobbyInterface* pLobbyInterface = NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
	if (pLobbyInterface == nullptr)
	{
		DEBUG_LOG(("NGMP_OnlineServices_LobbyInterface is not initialized!"));
		return;
	}

	LobbyEntry lobbyTryingToJoin = pLobbyInterface->GetLobbyTryingToJoin();
	UnicodeString lobbyName(from_utf8(lobbyTryingToJoin.name).c_str());
	GadgetStaticTextSetText(staticTextGameName, lobbyName);

	TheWindowManager->winSetFocus(textEntryGamePassword);
	TheWindowManager->winSetModal( parentPopup );

}

//-------------------------------------------------------------------------------------------------
/** PopupHostGameInput callback */
//-------------------------------------------------------------------------------------------------
WindowMsgHandledType PopupJoinGameInput( GameWindow *window, UnsignedInt msg, WindowMsgData mData1, WindowMsgData mData2 )
{
	switch( msg )
	{

		// --------------------------------------------------------------------------------------------
		case GWM_CHAR:
		{
			UnsignedByte key = mData1;
			UnsignedByte state = mData2;
//			if (buttonPushed)
//				break;

			switch( key )
			{

				// ----------------------------------------------------------------------------------------
				case KEY_ESC:
				{

					//
					// send a simulated selected event to the parent window of the
					// back/exit button
					//
					if( BitIsSet( state, KEY_STATE_UP ) )
					{
						GameSpyCloseOverlay(GSOVERLAY_GAMEPASSWORD);
						SetLobbyAttemptHostJoin( FALSE );
						parentPopup = nullptr;
					}

					// don't let key fall through anywhere else
					return MSG_HANDLED;

				}

			}

		}

	}

	return MSG_IGNORED;

}

//-------------------------------------------------------------------------------------------------
/** PopupHostGameSystem callback */
//-------------------------------------------------------------------------------------------------
WindowMsgHandledType PopupJoinGameSystem( GameWindow *window, UnsignedInt msg, WindowMsgData mData1, WindowMsgData mData2 )
{
  switch( msg )
	{

		// --------------------------------------------------------------------------------------------
		case GWM_CREATE:
		{

			break;

		}
    //---------------------------------------------------------------------------------------------
		case GWM_DESTROY:
		{
			buttonJoin = nullptr;
			parentPopup = nullptr;
			textEntryGamePassword = nullptr;
			break;

		}

		//---------------------------------------------------------------------------------------------
		case GBM_SELECTED:
		{
			GameWindow *control = (GameWindow *)mData1;
			if (control == nullptr)
				break;
			Int controlID = control->winGetWindowId();
			if (controlID == buttonCancelID)
			{
				GameSpyCloseOverlay(GSOVERLAY_GAMEPASSWORD);
				SetLobbyAttemptHostJoin( FALSE );
				parentPopup = nullptr;
				buttonJoin = nullptr;
			}
			else if (controlID == buttonJoinID || control == buttonJoin)
			{
				submitPassword();
			}
			break;
		}

    //----------------------------------------------------------------------------------------------
    case GWM_INPUT_FOCUS:
		{

			// if we're givin the opportunity to take the keyboard focus we must say we want it
			if( mData1 == TRUE )
				*(Bool *)mData2 = TRUE;

			break;

		}
    //---------------------------------------------------------------------------------------------
		case GEM_EDIT_DONE:
		{
			GameWindow *control = (GameWindow *)mData1;
			Int controlID = control->winGetWindowId();

      if( controlID == textEntryGamePasswordID )
			{
				submitPassword();
			}
			break;
		}
		default:
			return MSG_IGNORED;

	}

	return MSG_HANDLED;

}


//-----------------------------------------------------------------------------
// PRIVATE FUNCTIONS //////////////////////////////////////////////////////////
//-----------------------------------------------------------------------------

static void submitPassword()
{
	if (textEntryGamePassword == nullptr)
		return;

	UnicodeString txtInput;
	txtInput.set(GadgetTextEntryGetText(textEntryGamePassword));
	txtInput.trim();
	if (txtInput.isEmpty())
	{
		NetworkLog(ELogVerbosity::LOG_RELEASE, "[NGMP-PASSWORD] Join requested with an empty password");
		TheWindowManager->winSetFocus(textEntryGamePassword);
		return;
	}

	AsciiString password;
	password.translate(txtInput);
	GadgetTextEntrySetText(textEntryGamePassword, UnicodeString::TheEmptyString);
	joinGame(password);
}

static void joinGame( AsciiString password )
{
	NGMP_OnlineServices_LobbyInterface* pLobbyInterface = NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
	if (pLobbyInterface == nullptr)
	{
		DEBUG_LOG(("NGMP_OnlineServices_LobbyInterface is not initialized!"));
		GameSpyCloseOverlay(GSOVERLAY_GAMEPASSWORD);
		SetLobbyAttemptHostJoin(FALSE);
		parentPopup = nullptr;
		return;
	}

	LobbyEntry lobbyTryingToJoin = pLobbyInterface->GetLobbyTryingToJoin();

	if (lobbyTryingToJoin.lobbyID == -1)
	{
		GameSpyCloseOverlay(GSOVERLAY_GAMEPASSWORD);
		SetLobbyAttemptHostJoin(FALSE);
		parentPopup = NULL;
		return;
	}

#if defined(GENERALS_ONLINE)
	NetworkLog(ELogVerbosity::LOG_RELEASE, "[NGMP-PASSWORD] Joining lobby %d passworded=%d passwordLength=%d",
		lobbyTryingToJoin.lobbyID, lobbyTryingToJoin.passworded ? 1 : 0, password.getLength());
	pLobbyInterface->JoinLobby(lobbyTryingToJoin, password.str());
	DEBUG_LOG(("Attempting to join game %d(%s); password length=%d\n", lobbyTryingToJoin.lobbyID, lobbyTryingToJoin.name.c_str(), password.getLength()));
#else
	PeerRequest req;
	req.peerRequestType = PeerRequest::PEERREQUEST_JOINSTAGINGROOM;
	req.text = ourRoom->getGameName().str();
	req.stagingRoom.id = ourRoom->getID();
	req.password = password.str();
	TheGameSpyPeerMessageQueue->addRequest(req);
	DEBUG_LOG(("Attempting to join game %d(%ls) with password [%s]", ourRoom->getID(), ourRoom->getGameName().str(), password.str()));
#endif

	GameSpyCloseOverlay(GSOVERLAY_GAMEPASSWORD);
	parentPopup = nullptr;
	buttonJoin = nullptr;
}
