// Seed Edge Signals and Productivity Ideas for mock demo review

// --- Lookup IDs ---
Id fnSHA4  = 'a2yHn000003Km9SIAS'; // SHA-ASM-Station 4 Final Fit
Id fnSHA7  = 'a2yHn000003Km9TIAS'; // SHA-ASM-Station 7 Door Sub
Id fnSHA12 = 'a2yHn000003Km9UIAS'; // SHA-ASM-Station 12 Chassis
Id fnSHAB2 = 'a2yHn000003Km9VIAS'; // SHA-BODY-Station B2 Welding
Id fnFZ3   = 'a2yHn000003Km9WIAS'; // FZ-ASM-Station 3 Battery Module
Id fnFZ8   = 'a2yHn000003Km9XIAS'; // FZ-ASM-Station 8 EV Drive Unit

Id libMaterial  = 'a2wHn000007eN7oIAE'; // Material Flow Optimization
Id libStation   = 'a2wHn000007eN7pIAE'; // Station Layout Rearrangement
Id libWorkload  = 'a2wHn000007eN7qIAE'; // Workload Rebalance
Id libAutomation= 'a2wHn000007eN7rIAE'; // Automation Assist
Id libBinRepl   = 'a2wHn000007eN7tIAE'; // Bin Replenishment Process
Id libMicro     = 'a2wHn000007eN7sIAE'; // Micro-Stoppage Reduction
Id libLineBal   = 'a2wHn000007eN7uIAE'; // Line Balancing
Id libCrossTrain= 'a2wHn000007eN7vIAE'; // Cross-Training Program

// --- Edge Signals ---
List<GWB_Edge_Signal__c> signals = new List<GWB_Edge_Signal__c>{
    new GWB_Edge_Signal__c(
        Plant_Function__c = fnSHA4,  Station__c = 'Station 4',
        Signal_Type__c = 'Bin-Depletion', Risk__c = 'High',
        Current_Level__c = 8, Minutes_To_Empty__c = 12,
        Processed__c = true,
        Raw_JSON__c = '{"plant":"SHA","station":"Station 4","signal_type":"Bin-Depletion","risk":"High","current_level":8,"minutes_to_empty":12}'
    ),
    new GWB_Edge_Signal__c(
        Plant_Function__c = fnSHA7,  Station__c = 'Station 7',
        Signal_Type__c = 'Idle-Time', Risk__c = 'Medium',
        Current_Level__c = 0, Minutes_To_Empty__c = 0,
        Processed__c = true,
        Raw_JSON__c = '{"plant":"SHA","station":"Station 7","signal_type":"Idle-Time","risk":"Medium"}'
    ),
    new GWB_Edge_Signal__c(
        Plant_Function__c = fnSHA12, Station__c = 'Station 12',
        Signal_Type__c = 'Micro-Stoppage', Risk__c = 'High',
        Current_Level__c = 0, Minutes_To_Empty__c = 0,
        Processed__c = true,
        Raw_JSON__c = '{"plant":"SHA","station":"Station 12","signal_type":"Micro-Stoppage","risk":"High","stoppages_per_hour":14}'
    ),
    new GWB_Edge_Signal__c(
        Plant_Function__c = fnSHAB2, Station__c = 'Station B2',
        Signal_Type__c = 'Idle-Time', Risk__c = 'Low',
        Current_Level__c = 0, Minutes_To_Empty__c = 0,
        Processed__c = true,
        Raw_JSON__c = '{"plant":"SHA","station":"Station B2","signal_type":"Idle-Time","risk":"Low"}'
    ),
    new GWB_Edge_Signal__c(
        Plant_Function__c = fnFZ3,   Station__c = 'Station 3',
        Signal_Type__c = 'Bin-Depletion', Risk__c = 'High',
        Current_Level__c = 5, Minutes_To_Empty__c = 8,
        Processed__c = true,
        Raw_JSON__c = '{"plant":"FZ","station":"Station 3","signal_type":"Bin-Depletion","risk":"High","current_level":5,"minutes_to_empty":8}'
    ),
    new GWB_Edge_Signal__c(
        Plant_Function__c = fnFZ8,   Station__c = 'Station 8',
        Signal_Type__c = 'Micro-Stoppage', Risk__c = 'Medium',
        Current_Level__c = 0, Minutes_To_Empty__c = 0,
        Processed__c = false,
        Raw_JSON__c = '{"plant":"FZ","station":"Station 8","signal_type":"Micro-Stoppage","risk":"Medium","stoppages_per_hour":7}'
    )
};
insert signals;
System.debug('Edge Signals inserted: ' + signals.size());

// --- Productivity Ideas ---
List<GWB_Productivity_Idea__c> ideas = new List<GWB_Productivity_Idea__c>{
    // SHA Station 4 — Bin Replenishment → Approved
    new GWB_Productivity_Idea__c(
        Name = 'SHA Sta-4: Bin Replenishment Redesign',
        Plant_Function__c = fnSHA4,
        Idea_Library__c   = libBinRepl,
        Edge_Signal__c    = signals[0].Id,
        Status__c         = 'Approved',
        Idea_Type__c      = 'Permanent',
        AI_Generated__c   = true,
        FTE_Impact__c     = 1.2,
        Dollar_Impact__c  = 156000,
        Confidence_Score__c = 87,
        Effort__c         = 'Low',
        Assumptions__c    = 'Assumes bin replenishment route redesign with dedicated material handler. No capital investment required.',
        Benchmark_Evidence__c = 'Spring Hill Plant B: 1.1 FTE achieved Q3 2025 (Assembly). Factory Zero: 1.3 FTE Q4 2025.',
        Required_Validations__c = 'Safety review complete. Finance approved.',
        Risk_Notes__c     = 'Low risk — no line disruption during implementation.'
    ),
    // SHA Station 7 — Workload Rebalance → Approved
    new GWB_Productivity_Idea__c(
        Name = 'SHA Sta-7: Door Sub-Assembly Workload Rebalance',
        Plant_Function__c = fnSHA7,
        Idea_Library__c   = libWorkload,
        Edge_Signal__c    = signals[1].Id,
        Status__c         = 'Approved',
        Idea_Type__c      = 'Permanent',
        AI_Generated__c   = true,
        FTE_Impact__c     = 0.8,
        Dollar_Impact__c  = 104000,
        Confidence_Score__c = 82,
        Effort__c         = 'Medium',
        Assumptions__c    = 'Rebalance 3 tasks from Station 7 to Station 6 based on takt time analysis.',
        Benchmark_Evidence__c = 'Factory Zero Assembly: 0.9 FTE Q2 2025 via similar rebalance.',
        Required_Validations__c = 'Quality review required. IE sign-off needed.',
        Risk_Notes__c     = 'Medium — takt time disruption risk during transition week.'
    ),
    // SHA Station 12 — Micro-Stoppage → Pending Approval
    new GWB_Productivity_Idea__c(
        Name = 'SHA Sta-12: Chassis Line Micro-Stoppage Reduction',
        Plant_Function__c = fnSHA12,
        Idea_Library__c   = libMicro,
        Edge_Signal__c    = signals[2].Id,
        Status__c         = 'Pending Approval',
        Idea_Type__c      = 'Permanent',
        AI_Generated__c   = true,
        FTE_Impact__c     = 1.5,
        Dollar_Impact__c  = 195000,
        Confidence_Score__c = 79,
        Effort__c         = 'Medium',
        Assumptions__c    = 'Install error-proofing jigs at top 3 micro-stoppage points. 14 stoppages/hr → target <4.',
        Benchmark_Evidence__c = 'Spring Hill Body: 1.4 FTE Q1 2026. Lansing Delta: 1.6 FTE Q3 2025.',
        Required_Validations__c = 'Safety review required. Quality review required. Finance approval for jig capex ~$28K.',
        Risk_Notes__c     = 'Capital required. 2-week install window needed.'
    ),
    // SHA Body B2 — Station Layout → Pending Approval
    new GWB_Productivity_Idea__c(
        Name = 'SHA B2: Welding Station Layout Rearrangement',
        Plant_Function__c = fnSHAB2,
        Idea_Library__c   = libStation,
        Edge_Signal__c    = signals[3].Id,
        Status__c         = 'Pending Approval',
        Idea_Type__c      = 'Permanent',
        AI_Generated__c   = true,
        FTE_Impact__c     = 1.0,
        Dollar_Impact__c  = 130000,
        Confidence_Score__c = 75,
        Effort__c         = 'High',
        Assumptions__c    = 'Reposition 2 weld guns and consolidate fixture storage to reduce walk distance by ~40%.',
        Benchmark_Evidence__c = 'Spring Hill Assembly: 1.6 FTE Q3 2025 (EV context).',
        Required_Validations__c = 'Safety review required. Engineering sign-off for layout change.',
        Risk_Notes__c     = 'High effort — full weekend shutdown required for layout move.'
    ),
    // FZ Station 3 — Material Flow → Pending Approval
    new GWB_Productivity_Idea__c(
        Name = 'FZ Sta-3: Battery Module Material Flow Optimization',
        Plant_Function__c = fnFZ3,
        Idea_Library__c   = libMaterial,
        Edge_Signal__c    = signals[4].Id,
        Status__c         = 'Pending Approval',
        Idea_Type__c      = 'Permanent',
        AI_Generated__c   = true,
        FTE_Impact__c     = 0.9,
        Dollar_Impact__c  = 117000,
        Confidence_Score__c = 83,
        Effort__c         = 'Low',
        Assumptions__c    = 'Introduce milk-run delivery to Station 3 every 20 min. Eliminates manual bin trips.',
        Benchmark_Evidence__c = 'Factory Zero Assembly: 0.8 FTE Q4 2025 (EV battery context).',
        Required_Validations__c = 'Logistics team sign-off. No safety review needed.',
        Risk_Notes__c     = 'Low risk — no equipment changes required.'
    ),
    // FZ Station 8 — Line Balancing → Draft
    new GWB_Productivity_Idea__c(
        Name = 'FZ Sta-8: EV Drive Unit Line Balancing',
        Plant_Function__c = fnFZ8,
        Idea_Library__c   = libLineBal,
        Edge_Signal__c    = signals[5].Id,
        Status__c         = 'Draft',
        Idea_Type__c      = 'Permanent',
        AI_Generated__c   = true,
        FTE_Impact__c     = 0.7,
        Dollar_Impact__c  = 91000,
        Confidence_Score__c = 68,
        Effort__c         = 'Medium',
        Assumptions__c    = 'Redistribute 4 tasks from Station 8 across Stations 7 and 9 to eliminate bottleneck.',
        Benchmark_Evidence__c = 'Hamtramck Assembly: 0.6 FTE Q2 2025.',
        Required_Validations__c = 'IE study needed. Quality review required.',
        Risk_Notes__c     = 'Needs IE takt time validation before approval.'
    ),
    // SHA Station 4 — Cross-Training → Deferred
    new GWB_Productivity_Idea__c(
        Name = 'SHA Sta-4: Final Fit Cross-Training Program',
        Plant_Function__c = fnSHA4,
        Idea_Library__c   = libCrossTrain,
        Status__c         = 'Deferred',
        Idea_Type__c      = 'Temporary',
        AI_Generated__c   = true,
        FTE_Impact__c     = 0.5,
        Dollar_Impact__c  = 65000,
        Confidence_Score__c = 61,
        Effort__c         = 'Low',
        Start_Date__c     = Date.newInstance(2026, 7, 1),
        End_Date__c       = Date.newInstance(2026, 9, 30),
        Assumptions__c    = 'Cross-train 6 operators across Stations 3-5. Enables flex staffing during model changeover.',
        Benchmark_Evidence__c = 'Spring Hill: 0.4 FTE Q4 2025 (temporary program).',
        Required_Validations__c = 'Training team capacity check required.',
        Risk_Notes__c     = 'Deferred pending Q3 model changeover schedule confirmation.'
    ),
    // FZ Station 3 — Automation Assist → Rejected
    new GWB_Productivity_Idea__c(
        Name = 'FZ Sta-3: Automation Assist for Battery Tray Load',
        Plant_Function__c = fnFZ3,
        Idea_Library__c   = libAutomation,
        Status__c         = 'Rejected',
        Idea_Type__c      = 'Permanent',
        AI_Generated__c   = true,
        FTE_Impact__c     = 2.0,
        Dollar_Impact__c  = 260000,
        Confidence_Score__c = 55,
        Effort__c         = 'High',
        Assumptions__c    = 'Cobotic arm to assist battery tray loading. Capex ~$240K.',
        Benchmark_Evidence__c = 'No direct benchmark — emerging technology.',
        Required_Validations__c = 'Safety, Quality, Finance, Engineering sign-off all required.',
        Risk_Notes__c     = 'Rejected: capex not approved in Q2 budget cycle. Revisit Q4 2026.'
    )
};
insert ideas;
System.debug('Productivity Ideas inserted: ' + ideas.size());

// Summary
System.debug('=== SEED COMPLETE ===');
System.debug('Edge Signals: ' + [SELECT COUNT() FROM GWB_Edge_Signal__c]);
System.debug('Productivity Ideas: ' + [SELECT COUNT() FROM GWB_Productivity_Idea__c]);
System.debug('  Approved: '        + [SELECT COUNT() FROM GWB_Productivity_Idea__c WHERE Status__c = 'Approved']);
System.debug('  Pending Approval: '+ [SELECT COUNT() FROM GWB_Productivity_Idea__c WHERE Status__c = 'Pending Approval']);
System.debug('  Draft: '           + [SELECT COUNT() FROM GWB_Productivity_Idea__c WHERE Status__c = 'Draft']);
System.debug('  Deferred: '        + [SELECT COUNT() FROM GWB_Productivity_Idea__c WHERE Status__c = 'Deferred']);
System.debug('  Rejected: '        + [SELECT COUNT() FROM GWB_Productivity_Idea__c WHERE Status__c = 'Rejected']);
