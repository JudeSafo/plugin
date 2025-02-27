class TMDojo
{
    bool recording = false;
    MemoryBuffer membuff = MemoryBuffer(0);

    int prevRaceTime = -6666;
    int currentRaceTime = -6666;
    int latestRecordedTime = -6666;
    CTrackManiaNetwork@ network;


    // Player info
    string playerName;
    string playerLogin;
    string webId;

    // Idle detection
    vec3 latestPlayerPosition;
    int numSamePositions = 0;

    // Server status
    bool serverAvailable = false;
    bool checkingServer = false;

    // Session
    int checkSessionIdCount = 0;
    int maxCheckSessionId = 60;

    string pluginAuthUrl = "";

    bool pluginAuthed = false;
    bool isAuthenticating = false;
    bool authWindowOpened = false;

    TMDojo() {
        auto app = GetApp();
        @network = cast<CTrackManiaNetwork>(app.Network);
        startnew(Api::checkServerWaitForValidWebId);
    }

    void FillBuffer(CSceneVehicleVisState@ vis) {
        int gazAndBrake = 0;
        int gazPedal = vis.InputGasPedal > 0 ? 1 : 0;
        int isBraking = vis.InputBrakePedal > 0 ? 2 : 0;

        gazAndBrake |= gazPedal;
        gazAndBrake |= isBraking;

        membuff.Write(g_dojo.currentRaceTime);

        membuff.Write(vis.Position.x);
        membuff.Write(vis.Position.y);
        membuff.Write(vis.Position.z);

        membuff.Write(vis.WorldVel.x);
        membuff.Write(vis.WorldVel.y);
        membuff.Write(vis.WorldVel.z);

        membuff.Write(vis.FrontSpeed * 3.6f);

        membuff.Write(vis.InputSteer);
        membuff.Write(vis.FLSteerAngle);

        membuff.Write(gazAndBrake);

        membuff.Write(VehicleState::GetRPM(vis));
        membuff.Write(vis.CurGear);

        membuff.Write(vis.Up.x);
        membuff.Write(vis.Up.y);
        membuff.Write(vis.Up.z);

        membuff.Write(vis.Dir.x);
        membuff.Write(vis.Dir.y);
        membuff.Write(vis.Dir.z);

        uint8 fLGroundContactMaterial = vis.FLGroundContactMaterial;
        membuff.Write(fLGroundContactMaterial);
        membuff.Write(vis.FLSlipCoef);
        membuff.Write(vis.FLDamperLen);

        uint8 fRGroundContactMaterial = vis.FRGroundContactMaterial;
        membuff.Write(fRGroundContactMaterial);
        membuff.Write(vis.FRSlipCoef);
        membuff.Write(vis.FRDamperLen);

        uint8 rLGroundContactMaterial = vis.RLGroundContactMaterial;
        membuff.Write(rLGroundContactMaterial);
        membuff.Write(vis.RLSlipCoef);
        membuff.Write(vis.RLDamperLen);

        uint8 rRGroundContactMaterial = vis.RRGroundContactMaterial;
        membuff.Write(rRGroundContactMaterial);
        membuff.Write(vis.RRSlipCoef);
        membuff.Write(vis.RRDamperLen);
    }

    void Render()
	{
        // Do not start recording if the user is not authenticated or doesn't even have a SessionId
        if (!pluginAuthed || SessionId == "") {
            return;
        }

		auto app = GetApp();

		auto sceneVis = app.GameScene;
		if (@sceneVis is null || @app.Editor != null) {
			return;
		}

        if (@app.CurrentPlayground == null || app.CurrentPlayground.GameTerminals.get_Length() == 0 || @app.CurrentPlayground.GameTerminals[0].GUIPlayer == null) {
            return;
        }

        CSmPlayer@ smPlayer = cast<CSmPlayer>(app.CurrentPlayground.GameTerminals[0].GUIPlayer);
        CSmScriptPlayer@ smScript = cast<CSmScriptPlayer>(smPlayer.ScriptAPI);
        CGamePlaygroundUIConfig@ uiConfig = app.CurrentPlayground.UIConfigs[0];
        CGameCtnChallenge@ rootMap = app.RootMap;

        if (@smScript == null) {
            return;
        }

        CSceneVehicleVisState@ vis = null;

		CSmPlayer@ player = Player::GetViewingPlayer();

		if (player !is null && player.User.Name.Contains(network.PlayerInfo.Name)) {
			@vis = VehicleState::ViewingPlayerState();
		}

		if (vis is null) {
			return;
		}

		uint entityId = Dev::GetOffsetUint32(vis, 0);
		if ((entityId & 0xFF000000) == 0x04000000) {
			return;
		}

        if (this.checkingServer || !this.serverAvailable) {
            return;
        }

        auto playgroundScript = cast<CSmArenaRulesMode>(app.PlaygroundScript);

        bool hudOff = false;

        if (app.CurrentPlayground !is null && app.CurrentPlayground.Interface !is null) {
            if (!UI::IsGameUIVisible()) {
                hudOff = true;
                if (@playgroundScript == null) {
                    if (@app.Network.PlaygroundClientScriptAPI != null) {
                        auto playgroundClientScriptAPI = cast<CGamePlaygroundClientScriptAPI>(app.Network.PlaygroundClientScriptAPI);
                        if (@playgroundClientScriptAPI != null) {
                            g_dojo.currentRaceTime = playgroundClientScriptAPI.GameTime - smScript.StartTime;
                        }
                    }
                } else {
                    g_dojo.currentRaceTime = playgroundScript.Now - smScript.StartTime;
                }
            } else {
                g_dojo.currentRaceTime = smScript.CurrentRaceTime;
            }
        }

        if (Enabled && OverlayEnabled && !hudOff) {     
            drawRecordingOverlay();
        }

        if (!recording && g_dojo.currentRaceTime > -200 && g_dojo.currentRaceTime < 0) {
            recording = true;
        }

        if (recording) {
            
            if (uiConfig.UISequence == 11) {
                // Finished track
                print("[TMDojo]: Finished");

                ref @fh = FinishHandle();
                cast<FinishHandle>(fh).finished = true;
                @cast<FinishHandle>(fh).rootMap = rootMap;
                @cast<FinishHandle>(fh).uiConfig = uiConfig;
                @cast<FinishHandle>(fh).smScript = smScript;
                @cast<FinishHandle>(fh).network = network;
                cast<FinishHandle>(fh).endRaceTime = latestRecordedTime;

                // https://github.com/GreepTheSheep/openplanet-mx-random special thanks to greep for getting accurate endRaceTime

                int endRaceTimeAccurate = -1;

                CSmArenaRulesMode@ PlaygroundScript = cast<CSmArenaRulesMode>(app.PlaygroundScript);

                CGamePlayground@ GamePlayground = cast<CGamePlayground>(app.CurrentPlayground);
                if (PlaygroundScript !is null && GamePlayground.GameTerminals.get_Length() > 0) {
                    if (GamePlayground.GameTerminals[0].UISequence_Current == CGameTerminal::ESGamePlaygroundUIConfig__EUISequence::Finish && smScript !is null) {
                        auto ghost = PlaygroundScript.Ghost_RetrieveFromPlayer(smScript);
                        if (ghost !is null) {
                            if (ghost.Result.Time > 0 && ghost.Result.Time < 4294967295) endRaceTimeAccurate = ghost.Result.Time;
                            PlaygroundScript.DataFileMgr.Ghost_Release(ghost.Id);
                        } else endRaceTimeAccurate = -1;
                    } else endRaceTimeAccurate = -1;
                } else endRaceTimeAccurate = -1;

                if (endRaceTimeAccurate > 0) {
                    cast<FinishHandle>(fh).endRaceTime = endRaceTimeAccurate;
                }

                startnew(Api::PostRecordedData, fh);
            } else if (latestRecordedTime > 0 && g_dojo.currentRaceTime < 0) {
                // Give up
                print("[TMDojo]: Give up");

                ref @fh = FinishHandle();
                cast<FinishHandle>(fh).finished = false;
                @cast<FinishHandle>(fh).rootMap = rootMap;
                @cast<FinishHandle>(fh).uiConfig = uiConfig;
                @cast<FinishHandle>(fh).smScript = smScript;
                @cast<FinishHandle>(fh).network = network;
                cast<FinishHandle>(fh).endRaceTime = latestRecordedTime;
                
                startnew(Api::PostRecordedData, fh);
            } else {
                 // Record current data
                int timeSinceLastRecord = g_dojo.currentRaceTime - latestRecordedTime;
                if (timeSinceLastRecord > (1.0 / RECORDING_FPS) * 1000) {
                    // Keep track of the amount of samples for which the position did not changed, used to pause recording
                    if (Math::Abs(latestPlayerPosition.x - smScript.Position.x) < 0.001 &&
                        Math::Abs(latestPlayerPosition.y - smScript.Position.y) < 0.001 && 
                        Math::Abs(latestPlayerPosition.z - smScript.Position.z) < 0.001 ) {
                        numSamePositions += 1;
                    } else {
                        numSamePositions = 0;
                    }
                    // Fill buffer if player has moved recently
                    if (numSamePositions < RECORDING_FPS) {
                        FillBuffer(vis);
                        latestRecordedTime = g_dojo.currentRaceTime;
                    }

                    latestPlayerPosition = smScript.Position;
                }
            }
        }
	}
}