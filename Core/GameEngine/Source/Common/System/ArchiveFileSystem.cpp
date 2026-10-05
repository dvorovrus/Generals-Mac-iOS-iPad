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

//----------------------------------------------------------------------------
//
//                       Westwood Studios Pacific.
//
//                       Confidential Information
//                Copyright (C) 2001 - All Rights Reserved
//
//----------------------------------------------------------------------------
//
// Project:   Generals
//
// Module:    Game Engine Common
//
// File name: ArchiveFileSystem.cpp
//
// Created:   11/26/01 TR
//
//----------------------------------------------------------------------------

//----------------------------------------------------------------------------
//         Includes
//----------------------------------------------------------------------------

#include "PreRTS.h"
#include "Common/ArchiveFile.h"
#include "Common/ArchiveFileSystem.h"
#include "Common/AsciiString.h"
#include "Common/LocalFileSystem.h"
#include "Common/PerfTimer.h"
#if defined(GENERALS_ONLINE)
#include "GameNetwork/GeneralsOnline/NGMP_include.h"
#include "GameNetwork/GeneralsOnline/OnlineServices_Init.h"
#endif


//----------------------------------------------------------------------------
//         Externals
//----------------------------------------------------------------------------



//----------------------------------------------------------------------------
//         Defines
//----------------------------------------------------------------------------



//----------------------------------------------------------------------------
//         Private Types
//----------------------------------------------------------------------------


//----------------------------------------------------------------------------
//         Private Data
//----------------------------------------------------------------------------



//----------------------------------------------------------------------------
//         Public Data
//----------------------------------------------------------------------------

ArchiveFileSystem *TheArchiveFileSystem = nullptr;


//----------------------------------------------------------------------------
//         Private Prototypes
//----------------------------------------------------------------------------



//----------------------------------------------------------------------------
//         Private Functions
//----------------------------------------------------------------------------



//----------------------------------------------------------------------------
//         Public Functions
//----------------------------------------------------------------------------

//------------------------------------------------------
// ArchivedFileInfo
//------------------------------------------------------
ArchiveFileSystem::ArchiveFileSystem()
{
}

ArchiveFileSystem::~ArchiveFileSystem()
{
	ArchiveFileMap::iterator iter = m_archiveFileMap.begin();
	while (iter != m_archiveFileMap.end()) {
		ArchiveFile *file = iter->second;
		delete file;
		iter++;
	}
}

void ArchiveFileSystem::loadIntoDirectoryTree(ArchiveFile *archiveFile, Bool overwrite)
{

	FilenameList filenameList;

	archiveFile->getFileListInDirectory("", "", "*", filenameList, TRUE);

	FilenameListIter it = filenameList.begin();

	while (it != filenameList.end())
	{
		ArchivedDirectoryInfo *dirInfo = &m_rootDirectory;

		AsciiString path;
		AsciiString token;
		AsciiString tokenizer = *it;
		tokenizer.toLower();
		Bool infoInPath = tokenizer.nextToken(&token, "\\/");

		while (infoInPath && (!token.find('.') || tokenizer.find('.')))
		{
			path.concat(token);
			path.concat('\\');

			ArchivedDirectoryInfoMap::iterator tempiter = dirInfo->m_directories.find(token);
			if (tempiter == dirInfo->m_directories.end())
			{
				dirInfo = &(dirInfo->m_directories[token]);
				dirInfo->m_path = path;
				dirInfo->m_directoryName = token;
			}
			else
			{
				dirInfo = &tempiter->second;
			}

			infoInPath = tokenizer.nextToken(&token, "\\/");
		}

		ArchivedFileLocationMap::iterator fileIt;
		if (overwrite)
		{
			// When overwriting, try place the new value at the beginning of the key list.
			fileIt = dirInfo->m_files.find(token);
		}
		else
		{
			// Append to the end of the key list.
			fileIt = dirInfo->m_files.end();
		}

		dirInfo->m_files.insert(fileIt, std::make_pair(token, archiveFile));

#if defined(DEBUG_LOGGING) && ENABLE_FILESYSTEM_LOGGING
		{
			const stl::const_range<ArchivedFileLocationMap> range = stl::get_range(dirInfo->m_files, token, 0);
			if (range.distance() >= 2)
			{
				ArchivedFileLocationMap::const_iterator rangeIt0;
				ArchivedFileLocationMap::const_iterator rangeIt1;

				if (overwrite)
				{
					rangeIt0 = range.begin;
					rangeIt1 = std::next(rangeIt0);

					DEBUG_LOG(("ArchiveFileSystem::loadIntoDirectoryTree - adding file %s, archived in %s, overwriting same file in %s",
						it->str(),
						rangeIt0->second->getName().str(),
						rangeIt1->second->getName().str()
					));
				}
				else
				{
					rangeIt1 = std::prev(range.end);
					rangeIt0 = std::prev(rangeIt1);

					DEBUG_LOG(("ArchiveFileSystem::loadIntoDirectoryTree - adding file %s, archived in %s, overwritten by same file in %s",
						it->str(),
						rangeIt1->second->getName().str(),
						rangeIt0->second->getName().str()
					));
				}
			}
			else
			{
				DEBUG_LOG(("ArchiveFileSystem::loadIntoDirectoryTree - adding file %s, archived in %s", it->str(), archiveFile->getName().str()));
			}
		}
#endif

		it++;
	}
}

void ArchiveFileSystem::loadMods()
{
#if defined(GENERALS_ONLINE) && defined(GENERALS_ONLINE_COMMUNITY_PATCH_CHANGES)
	// The official Windows client loads this data patch from user data. Apple
	// full builds additionally carry it below the configured asset root so the
	// same deterministic INI set is available on iPad/macOS.
	const Bool explicitModActive = TheGlobalData != nullptr &&
		(TheGlobalData->m_modBIG.isNotEmpty() || TheGlobalData->m_modDir.isNotEmpty());
	if (!explicitModActive && NGMP_OnlineServicesManager::Settings.DataPacks_UseCommunityPatch())
	{
		AsciiString userPatch;
		userPatch.format("%sGeneralsOnlineGameData/500_900_CommunityPatch_CoreINI.big",
			TheGlobalData->getPath_UserData().str());
		const AsciiString portablePatch("GeneralsOnlineGameData/500_900_CommunityPatch_CoreINI.big");
		const AsciiString candidates[] = { userPatch, portablePatch };
		Bool loaded = FALSE;

		for (const AsciiString &patchPath : candidates)
		{
			if (!TheLocalFileSystem->doesFileExist(patchPath.str()))
				continue;

			ArchiveFile *archiveFile = openArchiveFile(patchPath.str());
			if (archiveFile == nullptr)
				continue;

			// Insert at the front so patched INIs override retail archives. A later
			// explicit -mod BIG/dir still gets the final say.
			loadIntoDirectoryTree(archiveFile, TRUE);
			m_archiveFileMap[patchPath] = archiveFile;
			NetworkLog(ELogVerbosity::LOG_RELEASE,
				"Loaded Generals Online community patch (%s)", patchPath.str());
			loaded = TRUE;
			break;
		}

		if (!loaded)
		{
			NetworkLog(ELogVerbosity::LOG_RELEASE,
				"Generals Online community patch missing; Windows lobby INI parity will be unavailable");
		}
	}
	else if (explicitModActive)
	{
		NetworkLog(ELogVerbosity::LOG_RELEASE,
			"Skipping Generals Online community patch because an explicit mod profile is active");
	}
#endif

	if (TheGlobalData->m_modBIG.isNotEmpty())
	{
		ArchiveFile *archiveFile = openArchiveFile(TheGlobalData->m_modBIG.str());

		if (archiveFile != nullptr) {
			DEBUG_LOG(("ArchiveFileSystem::loadMods - loading %s into the directory tree.", TheGlobalData->m_modBIG.str()));
			loadIntoDirectoryTree(archiveFile, TRUE);
			m_archiveFileMap[TheGlobalData->m_modBIG] = archiveFile;
			DEBUG_LOG(("ArchiveFileSystem::loadMods - %s inserted into the archive file map.", TheGlobalData->m_modBIG.str()));
		}
		else
		{
			DEBUG_LOG(("ArchiveFileSystem::loadMods - could not openArchiveFile(%s)", TheGlobalData->m_modBIG.str()));
		}
	}

	if (TheGlobalData->m_modDir.isNotEmpty())
	{
		MAYBE_UNUSED Bool ret = loadBigFilesFromDirectory(TheGlobalData->m_modDir, "*.big", TRUE);
		(void)ret;
		DEBUG_ASSERTLOG(ret, ("loadBigFilesFromDirectory(%s) returned FALSE!", TheGlobalData->m_modDir.str()));

		// iOS/portable mod diagnostics: identify which archive actually wins for
		// files that are critical to skirmish AI. Presence of !ContraXBeta2_AI.big
		// alone is not enough if another archive shadows its contents.
		static const char *criticalAIPaths[] = {
			"Data\\Scripts\\SkirmishScripts.scb",
			"Data\\INI\\AIData.ini",
			"Data\\INI\\Default\\AIData.ini",
			nullptr
		};
		for (Int i = 0; criticalAIPaths[i] != nullptr; ++i)
		{
			ArchiveFile *resolvedArchive = getArchiveFile(criticalAIPaths[i], 0);
			fprintf(stderr,
			        "[AI-DIAG] archive-resolution file='%s' archive='%s'\n",
			        criticalAIPaths[i],
			        resolvedArchive != nullptr ? resolvedArchive->getName().str() : "<missing>");
		}

		// Enhanced launcher validation: these probes are deliberately chosen from
		// each selectable visual group so iPad/macOS logs prove which archive won
		// after the -mod directory's filename-priority rules are applied.
		static const char *criticalVisualPaths[] = {
			"Art\\Textures\\abpwrplant.dds",                  // faction Vanilla vs HD
			"Art\\Textures\\mp_loaduserinterface.tga",       // UI HD/FHD/QHD
			"Art\\W3D\\exinfaa.w3d",                         // infantry icon 100/75/50
			"Art\\Textures\\SNAUserInterface512_001.tga",    // cameo SD/HD
			nullptr
		};
		for (Int i = 0; criticalVisualPaths[i] != nullptr; ++i)
		{
			ArchiveFile *resolvedArchive = getArchiveFile(criticalVisualPaths[i], 0);
			fprintf(stderr,
			        "[VISUAL-DIAG] archive-resolution file='%s' archive='%s'\n",
			        criticalVisualPaths[i],
			        resolvedArchive != nullptr ? resolvedArchive->getName().str() : "<missing>");
		}

		const char *onlinePatchProbe =
			"Data\\INI\\Object\\campaign\\america\\misc\\cine_u04_americaparachute.ini";
		ArchiveFile *probeArchive = getArchiveFile(onlinePatchProbe, 0);
		fprintf(stderr,
		        "[HUB-DATAPACK] archive-resolution file='%s' archive='%s'\n",
		        onlinePatchProbe,
		        probeArchive != nullptr ? probeArchive->getName().str() : "<missing>");
	}
}

Bool ArchiveFileSystem::doesFileExist(const Char *filename, FileInstance instance) const
{
	ArchivedDirectoryInfoResult result = const_cast<ArchiveFileSystem*>(this)->getArchivedDirectoryInfo(filename);

	if (!result.valid())
		return false;

	stl::const_range<ArchivedFileLocationMap> range = stl::get_range(result.dirInfo->m_files, result.lastToken, instance);

	return range.valid();
}

ArchivedDirectoryInfo* ArchiveFileSystem::friend_getArchivedDirectoryInfo(const Char* directory)
{
	ArchivedDirectoryInfoResult result = getArchivedDirectoryInfo(directory);

	return result.dirInfo;
}

ArchiveFileSystem::ArchivedDirectoryInfoResult ArchiveFileSystem::getArchivedDirectoryInfo(const Char* directory)
{
	ArchivedDirectoryInfoResult result;
	ArchivedDirectoryInfo* dirInfo = &m_rootDirectory;

	AsciiString token;
	AsciiString tokenizer = directory;
	tokenizer.toLower();
	Bool infoInPath = tokenizer.nextToken(&token, "\\/");

	while (infoInPath && (!token.find('.') || tokenizer.find('.')))
	{
		ArchivedDirectoryInfoMap::iterator tempiter = dirInfo->m_directories.find(token);
		if (tempiter != dirInfo->m_directories.end())
		{
			dirInfo = &tempiter->second;
			infoInPath = tokenizer.nextToken(&token, "\\/");
		}
		else
		{
			// the directory doesn't exist
			result.dirInfo = nullptr;
			result.lastToken = AsciiString::TheEmptyString;
			return result;
		}
	}

	result.dirInfo = dirInfo;
	result.lastToken = token;
	return result;
}

File * ArchiveFileSystem::openFile(const Char *filename, Int access, FileInstance instance)
{
	ArchiveFile* archive = getArchiveFile(filename, instance);

	if (archive == nullptr)
		return nullptr;

	return archive->openFile(filename, access);
}

Bool ArchiveFileSystem::getFileInfo(const AsciiString& filename, FileInfo *fileInfo, FileInstance instance) const
{
	if (fileInfo == nullptr) {
		return FALSE;
	}

	if (filename.isEmpty()) {
		return FALSE;
	}

	ArchiveFile* archive = getArchiveFile(filename, instance);

	if (archive == nullptr)
		return FALSE;

	return archive->getFileInfo(filename, fileInfo);
}

ArchiveFile* ArchiveFileSystem::getArchiveFile(const AsciiString& filename, FileInstance instance) const
{
	ArchivedDirectoryInfoResult result = const_cast<ArchiveFileSystem*>(this)->getArchivedDirectoryInfo(filename.str());

	if (!result.valid())
		return nullptr;

	stl::const_range<ArchivedFileLocationMap> range = stl::get_range(result.dirInfo->m_files, result.lastToken, instance);

	if (!range.valid())
		return nullptr;
	
	return range.get()->second;
}

void ArchiveFileSystem::getFileListInDirectory(const AsciiString& currentDirectory, const AsciiString& originalDirectory, const AsciiString& searchName, FilenameList &filenameList, Bool searchSubdirectories) const
{
	ArchiveFileMap::const_iterator it = m_archiveFileMap.begin();
	while (it != m_archiveFileMap.end()) {
		it->second->getFileListInDirectory(currentDirectory, originalDirectory, searchName, filenameList, searchSubdirectories);
		it++;
	}
}
