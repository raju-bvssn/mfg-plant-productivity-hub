// ── Plants ──────────────────────────────────────────────────────────────
GWB_Plant__c sha = new GWB_Plant__c(Name='Spring Hill Assembly', Plant_Code__c='SHA', Location__c='Spring Hill, TN', Active__c=true);
GWB_Plant__c fz  = new GWB_Plant__c(Name='Factory Zero Detroit',  Plant_Code__c='FZ',  Location__c='Detroit, MI',      Active__c=true);
insert new List<GWB_Plant__c>{sha, fz};

// ── Plant Shops ─────────────────────────────────────────────────────────
GWB_Plant_Shop__c shaAsm  = new GWB_Plant_Shop__c(Name='SHA Assembly Shop',  Plant__c=sha.Id, Shop_Type__c='Assembly', Active__c=true);
GWB_Plant_Shop__c shaBody = new GWB_Plant_Shop__c(Name='SHA Body Shop',      Plant__c=sha.Id, Shop_Type__c='Body',     Active__c=true);
GWB_Plant_Shop__c fzAsm   = new GWB_Plant_Shop__c(Name='FZ Assembly Shop',   Plant__c=fz.Id,  Shop_Type__c='Assembly', Active__c=true);
GWB_Plant_Shop__c fzPaint = new GWB_Plant_Shop__c(Name='FZ Paint Shop',      Plant__c=fz.Id,  Shop_Type__c='Paint',    Active__c=true);
insert new List<GWB_Plant_Shop__c>{shaAsm, shaBody, fzAsm, fzPaint};

// ── Plant Functions ─────────────────────────────────────────────────────
List<GWB_Plant_Function__c> funcs = new List<GWB_Plant_Function__c>{
    new GWB_Plant_Function__c(Name='SHA-ASM-Station 4 Final Fit', Plant_Shop__c=shaAsm.Id, Station__c='Station 4', Auth_Positions__c=12.0, Current_Headcount__c=11.5, Shift_Pattern__c='2-Shift', Active__c=true),
    new GWB_Plant_Function__c(Name='SHA-ASM-Station 7 Door Sub',  Plant_Shop__c=shaAsm.Id, Station__c='Station 7', Auth_Positions__c=8.0,  Current_Headcount__c=8.0,  Shift_Pattern__c='2-Shift', Active__c=true),
    new GWB_Plant_Function__c(Name='SHA-ASM-Station 12 Chassis',  Plant_Shop__c=shaAsm.Id, Station__c='Station 12',Auth_Positions__c=10.0, Current_Headcount__c=9.0,  Shift_Pattern__c='2-Shift', Active__c=true),
    new GWB_Plant_Function__c(Name='SHA-BODY-Station B2 Welding',  Plant_Shop__c=shaBody.Id,Station__c='Station B2',Auth_Positions__c=6.0,  Current_Headcount__c=6.0,  Shift_Pattern__c='2-Shift', Active__c=true),
    new GWB_Plant_Function__c(Name='FZ-ASM-Station 3 Battery Module', Plant_Shop__c=fzAsm.Id, Station__c='Station 3', Auth_Positions__c=14.0, Current_Headcount__c=13.0, Shift_Pattern__c='3-Shift', Active__c=true),
    new GWB_Plant_Function__c(Name='FZ-ASM-Station 8 EV Drive Unit',  Plant_Shop__c=fzAsm.Id, Station__c='Station 8', Auth_Positions__c=10.0, Current_Headcount__c=10.0, Shift_Pattern__c='3-Shift', Active__c=true),
    new GWB_Plant_Function__c(Name='FZ-PAINT-Zone P1 Prep',           Plant_Shop__c=fzPaint.Id,Station__c='Zone P1',  Auth_Positions__c=5.0,  Current_Headcount__c=4.5,  Shift_Pattern__c='2-Shift', Active__c=true)
};
insert funcs;

// ── HQ Targets ──────────────────────────────────────────────────────────
List<GWB_HQ_Target__c> targets = new List<GWB_HQ_Target__c>{
    new GWB_HQ_Target__c(Name='SHA Assembly Q2 2026 Target', Plant__c=sha.Id, Plant_Shop__c=shaAsm.Id, Target_FTE__c=5.0, Approved_FTE_Coverage__c=0.0, Quarter__c='Q2 2026', Production_Context__c='EV Silverado build mix transition. Takt time tightening from 72s to 64s in Q3. Focus on final fit and door sub stations.'),
    new GWB_HQ_Target__c(Name='FZ Assembly Q2 2026 Target',  Plant__c=fz.Id,  Plant_Shop__c=fzAsm.Id,  Target_FTE__c=3.0, Approved_FTE_Coverage__c=0.0, Quarter__c='Q2 2026', Production_Context__c='Silverado EV and Hummer EV mixed production. Battery module station is bottleneck. Targeting 3 FTE from automation and rebalance.')
};
insert targets;

// ── Idea Library ─────────────────────────────────────────────────────────
List<GWB_Idea_Library__c> ideas = new List<GWB_Idea_Library__c>{
    new GWB_Idea_Library__c(Name='Material Flow Optimization',    Idea_Category__c='Material Flow',      Applicable_Signal_Types__c='Bin-Depletion;Idle-Time',          Typical_FTE_Min__c=0.5, Typical_FTE_Max__c=1.5, Typical_Effort__c='Medium', Requires_Safety_Review__c=false, Requires_Quality_Review__c=false, Requires_Finance_Approval__c=false, Description__c='Redesign material replenishment routes and bin locations to reduce travel time and prevent stockouts.',     Preconditions__c='Requires current takt time and bin location data.'),
    new GWB_Idea_Library__c(Name='Station Layout Rearrangement',  Idea_Category__c='Layout',             Applicable_Signal_Types__c='Micro-Stoppage;Idle-Time',         Typical_FTE_Min__c=0.8, Typical_FTE_Max__c=2.0, Typical_Effort__c='High',   Requires_Safety_Review__c=true,  Requires_Quality_Review__c=true,  Requires_Finance_Approval__c=false, Description__c='Reconfigure workstation positions to reduce operator motion waste.',                                        Preconditions__c='Requires safety and ergonomics assessment.'),
    new GWB_Idea_Library__c(Name='Workload Rebalance',            Idea_Category__c='Workload Balancing', Applicable_Signal_Types__c='Micro-Stoppage;Idle-Time',         Typical_FTE_Min__c=0.5, Typical_FTE_Max__c=1.8, Typical_Effort__c='Medium', Requires_Safety_Review__c=false, Requires_Quality_Review__c=true,  Requires_Finance_Approval__c=false, Description__c='Redistribute tasks to eliminate bottleneck stations and idle time.',                                        Preconditions__c='Requires time study data for all affected stations.'),
    new GWB_Idea_Library__c(Name='Automation Assist',             Idea_Category__c='Automation',         Applicable_Signal_Types__c='Micro-Stoppage;Idle-Time',         Typical_FTE_Min__c=1.0, Typical_FTE_Max__c=3.0, Typical_Effort__c='High',   Requires_Safety_Review__c=true,  Requires_Quality_Review__c=false, Requires_Finance_Approval__c=true,  Description__c='Introduce collaborative robot to remove repetitive manual task from operator cycle time.',               Preconditions__c='Requires capital approval and safety risk assessment.'),
    new GWB_Idea_Library__c(Name='Micro-Stoppage Reduction',      Idea_Category__c='Process Improvement',Applicable_Signal_Types__c='Micro-Stoppage',                   Typical_FTE_Min__c=0.3, Typical_FTE_Max__c=1.0, Typical_Effort__c='Low',    Requires_Safety_Review__c=false, Requires_Quality_Review__c=true,  Requires_Finance_Approval__c=false, Description__c='Eliminate recurring micro-stoppages through root cause analysis and preventive maintenance.',             Preconditions__c='Requires maintenance logs and line OEE data.'),
    new GWB_Idea_Library__c(Name='Bin Replenishment Process',     Idea_Category__c='Material Flow',      Applicable_Signal_Types__c='Bin-Depletion',                    Typical_FTE_Min__c=0.4, Typical_FTE_Max__c=1.2, Typical_Effort__c='Low',    Requires_Safety_Review__c=false, Requires_Quality_Review__c=false, Requires_Finance_Approval__c=false, Description__c='Implement kanban or two-bin system with dedicated material handler routes.',                               Preconditions__c='Requires warehouse coordination and route planning.'),
    new GWB_Idea_Library__c(Name='Line Balancing',                Idea_Category__c='Workload Balancing', Applicable_Signal_Types__c='Idle-Time;Micro-Stoppage',         Typical_FTE_Min__c=0.6, Typical_FTE_Max__c=1.5, Typical_Effort__c='Medium', Requires_Safety_Review__c=false, Requires_Quality_Review__c=true,  Requires_Finance_Approval__c=false, Description__c='Re-sequence assembly operations across stations to achieve even cycle times.',                             Preconditions__c='Requires detailed time study and process mapping.'),
    new GWB_Idea_Library__c(Name='Cross-Training Program',        Idea_Category__c='Training',           Applicable_Signal_Types__c='Idle-Time',                        Typical_FTE_Min__c=0.3, Typical_FTE_Max__c=0.8, Typical_Effort__c='Low',    Requires_Safety_Review__c=false, Requires_Quality_Review__c=false, Requires_Finance_Approval__c=false, Description__c='Train operators on adjacent stations for flexible deployment during absenteeism.',                         Preconditions__c='Requires training schedule and skills matrix.'),
    new GWB_Idea_Library__c(Name='Scrap Reduction',               Idea_Category__c='Process Improvement',Applicable_Signal_Types__c='Quality-Defect',                   Typical_FTE_Min__c=0.4, Typical_FTE_Max__c=1.2, Typical_Effort__c='Medium', Requires_Safety_Review__c=false, Requires_Quality_Review__c=true,  Requires_Finance_Approval__c=false, Description__c='Implement error-proofing and process controls to reduce rework at defect-prone stations.',                  Preconditions__c='Requires quality data and defect Pareto analysis.'),
    new GWB_Idea_Library__c(Name='Setup Time Reduction',          Idea_Category__c='Process Improvement',Applicable_Signal_Types__c='Micro-Stoppage;Idle-Time',         Typical_FTE_Min__c=0.3, Typical_FTE_Max__c=0.9, Typical_Effort__c='Low',    Requires_Safety_Review__c=false, Requires_Quality_Review__c=false, Requires_Finance_Approval__c=false, Description__c='Apply SMED methodology to reduce changeover time at constrained stations.',                               Preconditions__c='Requires current setup time measurements.')
};
insert ideas;

// ── Plant Benchmarks ─────────────────────────────────────────────────────
// Map idea names to records for lookup
Map<String,Id> ideaMap = new Map<String,Id>();
for(GWB_Idea_Library__c i : ideas) ideaMap.put(i.Name, i.Id);

List<GWB_Plant_Benchmark__c> benchmarks = new List<GWB_Plant_Benchmark__c>{
    new GWB_Plant_Benchmark__c(Name='Lordstown ASM - Station Layout - Q3 2025',       Plant__c=sha.Id, Idea_Library__c=ideaMap.get('Station Layout Rearrangement'), Shop_Type__c='Assembly', Achieved_FTE__c=1.6, Quarter__c='Q3 2025', Production_Context__c='EV build mix',       Notes__c='Achieved 1.6 FTE by consolidating door sub and chassis prep into co-located stations.'),
    new GWB_Plant_Benchmark__c(Name='Orion ASM - Workload Rebalance - Q1 2026',       Plant__c=sha.Id, Idea_Library__c=ideaMap.get('Workload Rebalance'),           Shop_Type__c='Assembly', Achieved_FTE__c=1.2, Quarter__c='Q1 2026', Production_Context__c='Truck build',        Notes__c='Rebalanced 3 stations during takt change. Eliminated 1 floater position.'),
    new GWB_Plant_Benchmark__c(Name='Flint ASM - Material Flow - Q2 2025',            Plant__c=fz.Id,  Idea_Library__c=ideaMap.get('Material Flow Optimization'),   Shop_Type__c='Assembly', Achieved_FTE__c=0.9, Quarter__c='Q2 2025', Production_Context__c='Truck build',        Notes__c='Route consolidation for 4 bins reduced travel distance by 40%. Eliminated 1 material handler shift.'),
    new GWB_Plant_Benchmark__c(Name='FZ Pilot - Automation Assist - Q4 2025',         Plant__c=fz.Id,  Idea_Library__c=ideaMap.get('Automation Assist'),             Shop_Type__c='Assembly', Achieved_FTE__c=2.5, Quarter__c='Q4 2025', Production_Context__c='EV battery module', Notes__c='Cobot installed for battery module placement. Achieved 2.5 FTE reduction. CapEx $340K.'),
    new GWB_Plant_Benchmark__c(Name='Spring Hill - Bin Replenishment - Q1 2025',      Plant__c=sha.Id, Idea_Library__c=ideaMap.get('Bin Replenishment Process'),     Shop_Type__c='Assembly', Achieved_FTE__c=0.7, Quarter__c='Q1 2025', Production_Context__c='ICE mixed build',    Notes__c='Two-bin kanban reduced bin-depletion stoppages by 65%. Saved 0.7 FTE in material handler time.'),
    new GWB_Plant_Benchmark__c(Name='Hamtramck ASM - Line Balancing - Q3 2025',       Plant__c=fz.Id,  Idea_Library__c=ideaMap.get('Line Balancing'),                Shop_Type__c='Assembly', Achieved_FTE__c=1.3, Quarter__c='Q3 2025', Production_Context__c='EV build mix',       Notes__c='Re-sequenced 5 stations during EV takt transition. Saved 1.3 FTE by eliminating waiting time.'),
    new GWB_Plant_Benchmark__c(Name='Bowling Green - Micro-Stoppage Reduction - Q2 2025', Plant__c=sha.Id, Idea_Library__c=ideaMap.get('Micro-Stoppage Reduction'), Shop_Type__c='Assembly', Achieved_FTE__c=0.6, Quarter__c='Q2 2025', Production_Context__c='Sports car build',   Notes__c='PM schedule optimization reduced micro-stoppages by 55%. Saved 0.6 FTE in recovery time.'),
    new GWB_Plant_Benchmark__c(Name='Lansing - Cross-Training - Q4 2025',             Plant__c=fz.Id,  Idea_Library__c=ideaMap.get('Cross-Training Program'),        Shop_Type__c='Assembly', Achieved_FTE__c=0.5, Quarter__c='Q4 2025', Production_Context__c='Truck build',        Notes__c='12 operators cross-trained on 2 adjacent stations. Reduced floater dependency by 0.5 FTE.')
};
insert benchmarks;

System.debug('Seed data loaded successfully.');
System.debug('Plants: ' + [SELECT COUNT() FROM GWB_Plant__c]);
System.debug('Shops: ' + [SELECT COUNT() FROM GWB_Plant_Shop__c]);
System.debug('Functions: ' + [SELECT COUNT() FROM GWB_Plant_Function__c]);
System.debug('HQ Targets: ' + [SELECT COUNT() FROM GWB_HQ_Target__c]);
System.debug('Idea Library: ' + [SELECT COUNT() FROM GWB_Idea_Library__c]);
System.debug('Benchmarks: ' + [SELECT COUNT() FROM GWB_Plant_Benchmark__c]);
