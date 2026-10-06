#include "GameNetwork/GeneralsOnline/OnlineServices_SmokeTest.h"

#include "Common/GameEngine.h"
#include "Common/GlobalData.h"
#include "GameLogic/GameLogic.h"
#include "GameNetwork/GeneralsOnline/NGMPGame.h"
#include "GameNetwork/GeneralsOnline/NGMP_interfaces.h"
#include "GameNetwork/GeneralsOnline/NetworkMesh.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <list>
#include <string>
#include <utility>
#include <vector>

namespace
{
	using Clock = std::chrono::steady_clock;

	enum class SmokeRole
	{
		None,
		Host,
		Guest
	};

	enum class SmokePhase
	{
		Disabled,
		Bootstrap,
		Login,
		CreatingLobby,
		SearchingLobby,
		JoiningLobby,
		WaitingForPeer,
		CheckingMesh,
		WaitingForStart,
		WaitingForGameplay,
		Playing,
		Finished
	};

	struct SmokeState
	{
		bool active = false;
		bool finished = false;
		bool searchInFlight = false;
		bool joinInFlight = false;
		bool meshCheckInFlight = false;
		bool guestReadySent = false;
		SmokeRole role = SmokeRole::None;
		SmokePhase phase = SmokePhase::Disabled;
		std::string roomName;
		std::string mapPath = "Maps\\Alpine Assault\\Alpine Assault.map";
		std::string mapDisplayName = "Alpine Assault";
		std::string resultPath;
		int timeoutSeconds = 150;
		int gameplayFrames = 300;
		int64_t lobbyID = -1;
		int64_t userID = -1;
		UnsignedInt gameplayStartFrame = 0;
		Clock::time_point startedAt;
		Clock::time_point nextSearchAt;
		Clock::time_point nextMeshCheckAt;
		Clock::time_point exitAt;
	};

	SmokeState g_smoke;

	std::string GetEnv(const char* name, const char* fallback = "")
	{
		const char* value = std::getenv(name);
		return value != nullptr && value[0] != '\0' ? std::string(value) : std::string(fallback);
	}

	int GetPositiveEnvInt(const char* name, int fallback)
	{
		const std::string value = GetEnv(name);
		if (value.empty())
			return fallback;

		char* end = nullptr;
		const long parsed = std::strtol(value.c_str(), &end, 10);
		if (end == value.c_str() || *end != '\0' || parsed <= 0 || parsed > 36000)
			return fallback;
		return static_cast<int>(parsed);
	}

	SmokeRole GetConfiguredRole()
	{
		std::string role = GetEnv("GX_ONLINE_SMOKE_ROLE");
		std::transform(role.begin(), role.end(), role.begin(), [](unsigned char c) {
			return static_cast<char>(std::tolower(c));
		});
		if (role == "host")
			return SmokeRole::Host;
		if (role == "guest")
			return SmokeRole::Guest;
		return SmokeRole::None;
	}

	const char* RoleName()
	{
		return g_smoke.role == SmokeRole::Host ? "host" : g_smoke.role == SmokeRole::Guest ? "guest" : "none";
	}

	void WriteResult(bool success, const std::string& detail)
	{
		if (g_smoke.resultPath.empty())
			return;

		std::ofstream out(g_smoke.resultPath, std::ios::out | std::ios::trunc);
		if (!out.is_open())
		{
			NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] Could not write result file: %s", g_smoke.resultPath.c_str());
			return;
		}

		out << "status=" << (success ? "PASS" : "FAIL") << "\n";
		out << "role=" << RoleName() << "\n";
		out << "detail=" << detail << "\n";
		out << "lobby_id=" << g_smoke.lobbyID << "\n";
		out << "user_id=" << g_smoke.userID << "\n";
		if (TheGameLogic != nullptr)
			out << "frame=" << TheGameLogic->getFrame() << "\n";
	}

	void Finish(bool success, const std::string& detail)
	{
		if (!g_smoke.active || g_smoke.finished)
			return;

		g_smoke.finished = true;
		g_smoke.phase = SmokePhase::Finished;
		WriteResult(success, detail);
		NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] %s role=%s lobby=%lld detail=%s",
			success ? "PASS" : "FAIL", RoleName(), static_cast<long long>(g_smoke.lobbyID), detail.c_str());

		// Give the peer enough time to observe the same terminal state and flush logs.
		g_smoke.exitAt = Clock::now() + std::chrono::milliseconds(2500);
	}

	void RegisterStartCallback()
	{
		NGMP_OnlineServices_LobbyInterface* lobby =
			NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
		if (lobby == nullptr)
		{
			Finish(false, "lobby interface missing while registering start callback");
			return;
		}

		lobby->RegisterForGameStartPacket([]()
			{
				if (!g_smoke.active || g_smoke.finished)
					return;

				NGMP_OnlineServices_LobbyInterface* currentLobby =
					NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
				NGMPGame* lobbyGame = currentLobby == nullptr ? nullptr : currentLobby->GetCurrentGame();
				if (currentLobby == nullptr || lobbyGame == nullptr || !lobbyGame->isInGame() || TheNGMPGame == nullptr)
				{
					Finish(false, "START_GAME arrived without a valid lobby game");
					return;
				}

				NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] START_GAME received; launching headless match");
				*TheNGMPGame = *lobbyGame;
				TheNGMPGame->startGame(0);
				g_smoke.phase = SmokePhase::WaitingForGameplay;
			});
	}

	void StartHost()
	{
		NGMP_OnlineServices_LobbyInterface* lobby =
			NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
		if (lobby == nullptr)
		{
			Finish(false, "lobby interface missing after login");
			return;
		}

		RegisterStartCallback();
		if (g_smoke.finished)
			return;

		lobby->RegisterForCreateLobbyCallback([](bool success)
			{
				if (!g_smoke.active || g_smoke.finished)
					return;
				if (!success)
				{
					Finish(false, "CreateLobby failed");
					return;
				}

				NGMP_OnlineServices_LobbyInterface* currentLobby =
					NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
				if (currentLobby == nullptr || !currentLobby->IsInLobby())
				{
					Finish(false, "CreateLobby callback succeeded but current lobby is missing");
					return;
				}

				g_smoke.lobbyID = currentLobby->GetCurrentLobby().lobbyID;
				g_smoke.phase = SmokePhase::WaitingForPeer;
				NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] host created room '%s' id=%lld",
					g_smoke.roomName.c_str(), static_cast<long long>(g_smoke.lobbyID));
			});

		g_smoke.phase = SmokePhase::CreatingLobby;
		const UnicodeString roomName(from_utf8(g_smoke.roomName).c_str());
		const UnicodeString mapName(from_utf8(g_smoke.mapDisplayName).c_str());
		const AsciiString mapPath(g_smoke.mapPath.c_str());
		lobby->CreateLobby(roomName, mapName, mapPath, true, 2, false, false,
			TheGlobalData->m_defaultStartingCash.countMoney(), false, std::string(), false);
	}

	void SearchGuest()
	{
		if (g_smoke.searchInFlight || g_smoke.joinInFlight)
			return;

		NGMP_OnlineServices_LobbyInterface* lobby =
			NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
		if (lobby == nullptr)
		{
			Finish(false, "lobby interface missing while searching");
			return;
		}

		g_smoke.searchInFlight = true;
		lobby->SearchForLobbies(nullptr, [](std::vector<LobbyEntry> lobbies)
			{
				g_smoke.searchInFlight = false;
				if (!g_smoke.active || g_smoke.finished || g_smoke.joinInFlight)
					return;

				auto match = std::find_if(lobbies.begin(), lobbies.end(), [](const LobbyEntry& entry)
					{
						return entry.name == g_smoke.roomName;
					});
				if (match == lobbies.end())
				{
					g_smoke.nextSearchAt = Clock::now() + std::chrono::seconds(1);
					return;
				}

				if (match->exe_crc != TheGlobalData->m_exeCRC || match->ini_crc != TheGlobalData->m_iniCRC)
				{
					Finish(false, "target room CRC does not match this client");
					return;
				}

				NGMP_OnlineServices_LobbyInterface* currentLobby =
					NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
				if (currentLobby == nullptr)
				{
					Finish(false, "lobby interface disappeared before join");
					return;
				}

				g_smoke.joinInFlight = true;
				g_smoke.phase = SmokePhase::JoiningLobby;
				g_smoke.lobbyID = match->lobbyID;
				currentLobby->RegisterForJoinLobbyCallback([](EJoinLobbyResult result)
					{
						g_smoke.joinInFlight = false;
						if (!g_smoke.active || g_smoke.finished)
							return;
						if (result != EJoinLobbyResult::JoinLobbyResult_Success)
						{
							Finish(false, "JoinLobby failed");
							return;
						}

						NGMP_OnlineServices_LobbyInterface* joinedLobby =
							NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
						if (joinedLobby == nullptr || !joinedLobby->IsInLobby())
						{
							Finish(false, "join callback succeeded but current lobby is missing");
							return;
						}

						g_smoke.lobbyID = joinedLobby->GetCurrentLobby().lobbyID;
						g_smoke.phase = SmokePhase::WaitingForPeer;
						RegisterStartCallback();

						std::shared_ptr<WebSocket> ws = NGMP_OnlineServicesManager::GetWebSocket();
						if (ws != nullptr)
						{
							ws->SendData_MarkReady(true);
							g_smoke.guestReadySent = true;
						}

						NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] guest joined room '%s' id=%lld",
							g_smoke.roomName.c_str(), static_cast<long long>(g_smoke.lobbyID));
					});
				currentLobby->JoinLobby(*match, std::string());
			});
	}

	void OnLoggedIn(ELoginResult result)
	{
		if (!g_smoke.active || g_smoke.finished)
			return;

		if (result != ELoginResult::Success)
		{
			Finish(false, "cached credential login failed; prepare the smoke profile once in the normal Online UI");
			return;
		}

		NGMP_OnlineServices_AuthInterface* auth =
			NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_AuthInterface>();
		if (auth == nullptr)
		{
			Finish(false, "auth interface missing after login");
			return;
		}

		g_smoke.userID = auth->GetUserID();
		NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] login complete role=%s user=%lld",
			RoleName(), static_cast<long long>(g_smoke.userID));

		if (g_smoke.role == SmokeRole::Host)
			StartHost();
		else
		{
			g_smoke.phase = SmokePhase::SearchingLobby;
			g_smoke.nextSearchAt = Clock::now();
		}
	}

	void StartLogin()
	{
		if (!g_smoke.active || g_smoke.finished)
			return;

		NGMP_OnlineServices_AuthInterface* auth =
			NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_AuthInterface>();
		if (auth == nullptr)
		{
			Finish(false, "auth interface missing during bootstrap");
			return;
		}

		g_smoke.phase = SmokePhase::Login;
		auth->RegisterForLoginCallback(OnLoggedIn);
		auth->BeginLogin();
	}

	bool HostLobbyHasReadyPeer(const LobbyEntry& lobby)
	{
		int humanCount = 0;
		for (const LobbyMemberEntry& member : lobby.members)
		{
			if (!member.IsHuman())
				continue;
			++humanCount;
			if (!member.m_bIsReady)
				return false;
		}
		return humanCount >= 2;
	}

	void TickHostPeerAndMesh()
	{
		NGMP_OnlineServices_LobbyInterface* lobby =
			NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
		if (lobby == nullptr || !lobby->IsInLobby())
		{
			Finish(false, "host lost current lobby");
			return;
		}

		const LobbyEntry& entry = lobby->GetCurrentLobby();
		if (!HostLobbyHasReadyPeer(entry))
			return;

		if (g_smoke.meshCheckInFlight || Clock::now() < g_smoke.nextMeshCheckAt)
			return;

		std::shared_ptr<WebSocket> ws = NGMP_OnlineServicesManager::GetWebSocket();
		if (ws == nullptr || !ws->IsConnected())
		{
			Finish(false, "websocket disconnected before mesh check");
			return;
		}

		g_smoke.phase = SmokePhase::CheckingMesh;
		g_smoke.meshCheckInFlight = true;
		NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] host starting full-mesh connectivity check");
		ws->SendData_StartFullMeshConnectivityCheck(
			[](bool connected, std::list<std::pair<int64_t, int64_t>>, std::string reason)
			{
				g_smoke.meshCheckInFlight = false;
				if (!g_smoke.active || g_smoke.finished)
					return;

				if (!connected)
				{
					NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] mesh not ready yet: %s", reason.c_str());
					g_smoke.phase = SmokePhase::WaitingForPeer;
					g_smoke.nextMeshCheckAt = Clock::now() + std::chrono::seconds(2);
					return;
				}

				NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] full mesh connected; requesting START_GAME");
				g_smoke.phase = SmokePhase::WaitingForStart;
				std::shared_ptr<WebSocket> startWS = NGMP_OnlineServicesManager::GetWebSocket();
				if (startWS == nullptr || !startWS->IsConnected())
				{
					Finish(false, "websocket disconnected after successful mesh check");
					return;
				}
				startWS->SendData_StartGame();
			});
	}

	void TickGuestPeer()
	{
		NGMP_OnlineServices_LobbyInterface* lobby =
			NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
		if (lobby == nullptr || !lobby->IsInLobby())
			return;

		const LobbyEntry& entry = lobby->GetCurrentLobby();
		NetworkMesh* mesh = lobby->GetNetworkMeshForLobby();
		if (mesh == nullptr || entry.owner == -1)
			return;

		PlayerConnection* hostConnection = mesh->GetConnectionForUser(entry.owner);
		if (hostConnection != nullptr && hostConnection->GetState() == EConnectionState::CONNECTED_DIRECT)
		{
			if (!g_smoke.guestReadySent)
			{
				std::shared_ptr<WebSocket> ws = NGMP_OnlineServicesManager::GetWebSocket();
				if (ws != nullptr)
				{
					ws->SendData_MarkReady(true);
					g_smoke.guestReadySent = true;
				}
			}
			g_smoke.phase = SmokePhase::WaitingForStart;
		}
	}

	void TickGameplay()
	{
		if (TheGameLogic == nullptr)
			return;

		if (g_smoke.phase == SmokePhase::WaitingForGameplay)
		{
			if (!TheGameLogic->isInGame() || TheGameLogic->isInShellGame() || TheGameLogic->IsLoadScreenActive())
				return;

			g_smoke.gameplayStartFrame = TheGameLogic->getFrame();
			g_smoke.phase = SmokePhase::Playing;
			NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] gameplay entered at frame %u; validating %d frames",
				g_smoke.gameplayStartFrame, g_smoke.gameplayFrames);
			return;
		}

		if (g_smoke.phase == SmokePhase::Playing)
		{
			const UnsignedInt currentFrame = TheGameLogic->getFrame();
			if (currentFrame >= g_smoke.gameplayStartFrame + static_cast<UnsignedInt>(g_smoke.gameplayFrames))
				Finish(true, "two-client Online match reached gameplay frame target");
		}
	}
}

namespace OnlineSmokeTest
{
	bool IsEnabled()
	{
		return GetConfiguredRole() != SmokeRole::None;
	}

	void Init()
	{
		if (!IsEnabled() || g_smoke.active)
			return;

		g_smoke = SmokeState();
		g_smoke.active = true;
		g_smoke.role = GetConfiguredRole();
		g_smoke.phase = SmokePhase::Bootstrap;
		g_smoke.roomName = GetEnv("GX_ONLINE_SMOKE_ROOM", "GX-AUTO-SMOKE");
		g_smoke.mapPath = GetEnv("GX_ONLINE_SMOKE_MAP", g_smoke.mapPath.c_str());
		g_smoke.resultPath = GetEnv("GX_ONLINE_SMOKE_RESULT");
		g_smoke.timeoutSeconds = GetPositiveEnvInt("GX_ONLINE_SMOKE_TIMEOUT_SEC", 150);
		g_smoke.gameplayFrames = GetPositiveEnvInt("GX_ONLINE_SMOKE_FRAMES", 300);
		g_smoke.startedAt = Clock::now();
		g_smoke.nextSearchAt = g_smoke.startedAt;
		g_smoke.nextMeshCheckAt = g_smoke.startedAt;

		NetworkLog(ELogVerbosity::LOG_RELEASE,
			"[GO-SMOKE] enabled role=%s room='%s' timeout=%ds frames=%d",
			RoleName(), g_smoke.roomName.c_str(), g_smoke.timeoutSeconds, g_smoke.gameplayFrames);

		NGMP_OnlineServicesManager* manager = NGMP_OnlineServicesManager::GetInstance();
		if (manager == nullptr)
		{
			Finish(false, "Online services manager was not created");
			return;
		}

#if defined(__APPLE__)
		manager->PrepareAppleNetworkCRC([]()
			{
				NetworkLog(ELogVerbosity::LOG_RELEASE, "[GO-SMOKE] Apple network CRC prepared");
				StartLogin();
			});
#else
		StartLogin();
#endif
	}

	void Tick()
	{
		if (!g_smoke.active)
			return;

		const Clock::time_point now = Clock::now();

		if (g_smoke.finished)
		{
			if (now >= g_smoke.exitAt && TheGameEngine != nullptr)
				TheGameEngine->setQuitting(TRUE);
			return;
		}

		if (std::chrono::duration_cast<std::chrono::seconds>(now - g_smoke.startedAt).count() >= g_smoke.timeoutSeconds)
		{
			Finish(false, "global smoke-test timeout");
			return;
		}

		if (g_smoke.role == SmokeRole::Guest && g_smoke.phase == SmokePhase::SearchingLobby && now >= g_smoke.nextSearchAt)
			SearchGuest();

		if (g_smoke.phase == SmokePhase::WaitingForPeer || g_smoke.phase == SmokePhase::CheckingMesh)
		{
			if (g_smoke.role == SmokeRole::Host)
				TickHostPeerAndMesh();
			else
				TickGuestPeer();
		}

		if (g_smoke.phase == SmokePhase::WaitingForGameplay || g_smoke.phase == SmokePhase::Playing)
			TickGameplay();
	}

	void Shutdown()
	{
		if (!g_smoke.active)
			return;

		NGMP_OnlineServices_AuthInterface* auth =
			NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_AuthInterface>();
		if (auth != nullptr)
			auth->DeregisterForLoginCallback();

		NGMP_OnlineServices_LobbyInterface* lobby =
			NGMP_OnlineServicesManager::GetInterface<NGMP_OnlineServices_LobbyInterface>();
		if (lobby != nullptr)
		{
			lobby->DeregisterForCreateLobbyCallback();
			lobby->DeregisterForJoinLobbyCallback();
			lobby->DeregisterForSearchForLobbiesCallback();
			lobby->DeregisterForGameStartPacket();
		}

		std::shared_ptr<WebSocket> ws = NGMP_OnlineServicesManager::GetWebSocket();
		if (ws != nullptr)
			ws->ClearConnectivityCheckCallback();

		g_smoke.active = false;
	}
}
