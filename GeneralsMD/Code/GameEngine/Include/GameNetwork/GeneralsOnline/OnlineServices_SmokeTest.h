#pragma once

namespace OnlineSmokeTest
{
	// Enabled only when GX_ONLINE_SMOKE_ROLE is set to "host" or "guest".
	bool IsEnabled();

	// Starts the non-interactive Generals Online E2E flow. The Online services
	// manager must already exist and be initialized.
	void Init();

	// Called from NGMP_OnlineServicesManager::Tick().
	void Tick();

	// Detaches callbacks before Online services are destroyed.
	void Shutdown();
}
