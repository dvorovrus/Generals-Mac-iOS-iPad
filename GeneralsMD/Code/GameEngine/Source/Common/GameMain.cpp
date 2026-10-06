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

// GameMain.cpp
// The main entry point for the game
// Author: Michael S. Booth, April 2001

#include "PreRTS.h"	// This must go first in EVERY cpp file in the GameEngine

#include "Common/FramePacer.h"
#include "Common/GameEngine.h"
#include "Common/ReplaySimulation.h"
#if defined(GENERALS_ONLINE)
#include "GameNetwork/GeneralsOnline/OnlineServices_Init.h"
#include "GameNetwork/GeneralsOnline/OnlineServices_SmokeTest.h"
#endif


/**
 * This is the entry point for the game system.
 */
Int GameMain()
{
	int exitcode = 0;
	// initialize the game engine using factory function
	TheFramePacer = new FramePacer();
	TheFramePacer->enableFramesPerSecondLimit(TRUE);
	TheGameEngine = CreateGameEngine();
	TheGameEngine->init();

#if defined(GENERALS_ONLINE)
	// Headless Online smoke runs never enter the multiplayer menu, so bootstrap
	// the same services that StartPatchCheck normally creates for an interactive run.
	if (OnlineSmokeTest::IsEnabled())
	{
		NGMP_OnlineServicesManager::CreateInstance();
		NGMP_OnlineServicesManager* onlineServices = NGMP_OnlineServicesManager::GetInstance();
		if (onlineServices != nullptr)
		{
			onlineServices->Init();
			OnlineSmokeTest::Init();
		}
		else
		{
			TheGameEngine->setQuitting(TRUE);
		}
	}
#endif

	if (!TheGlobalData->m_simulateReplays.empty())
	{
		exitcode = ReplaySimulation::simulateReplays(TheGlobalData->m_simulateReplays, TheGlobalData->m_simulateReplayJobs);
	}
	else
	{
		// run it
		TheGameEngine->execute();
	}

	// since execute() returned, we are exiting the game
	delete TheFramePacer;
	TheFramePacer = nullptr;
	delete TheGameEngine;
	TheGameEngine = nullptr;

	return exitcode;
}

