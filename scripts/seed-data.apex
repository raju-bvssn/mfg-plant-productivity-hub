// PlantIQ — Demo Seed Data
// Run via: sf apex run --file scripts/seed-data.apex --target-org gwb-demo
// Safe to run multiple times — checks for existing records before inserting.

// ── 1. Plants ────────────────────────────────────────────────────────────────
List<GWB_Plant__c> plants = new List<GWB_Plant__c>();
Map<String, GWB_Plant__c> plantByCode = new Map<String, GWB_Plant__c>();

for (GWB_Plant__c p : [SELECT Id, Plant_Code__c FROM GWB_Plant__c
                        WHERE Plant_Code__c IN ('FLINT-1','WARREN-3','LANSING-2')]) {
    plantByCode.put(p.Plant_Code__c, p);
}

if (!plantByCode.containsKey('FLINT-1')) {
    plants.add(new GWB_Plant__c(Name='Flint Assembly Plant', Plant_Code__c='FLINT-1',
                                Location__c='Flint, MI', Active__c=true));
}
if (!plantByCode.containsKey('WARREN-3')) {
    plants.add(new GWB_Plant__c(Name='Warren Transmission', Plant_Code__c='WARREN-3',
                                Location__c='Warren, MI', Active__c=true));
}
if (!plantByCode.containsKey('LANSING-2')) {
    plants.add(new GWB_Plant__c(Name='Lansing Grand River', Plant_Code__c='LANSING-2',
                                Location__c='Lansing, MI', Active__c=true));
}
if (!plants.isEmpty()) {
    insert plants;
    for (GWB_Plant__c p : plants) plantByCode.put(p.Plant_Code__c, p);
}
System.debug('[Seed] Plants ready: ' + plantByCode.keySet());

// ── 2. Plant Shops ───────────────────────────────────────────────────────────
List<GWB_Plant_Shop__c> shops = new List<GWB_Plant_Shop__c>();
Map<String, GWB_Plant_Shop__c> shopByKey = new Map<String, GWB_Plant_Shop__c>();

for (GWB_Plant_Shop__c s : [SELECT Id, Name, Plant__r.Plant_Code__c FROM GWB_Plant_Shop__c]) {
    shopByKey.put(s.Plant__r.Plant_Code__c + ':' + s.Name, s);
}

Map<String, String[]> shopDefs = new Map<String, String[]>{
    'FLINT-1:Body Shop'    => new String[]{ 'FLINT-1',   'Body Shop',   'Body' },
    'FLINT-1:Paint Shop'   => new String[]{ 'FLINT-1',   'Paint Shop',  'Paint' },
    'WARREN-3:Trim Shop'   => new String[]{ 'WARREN-3',  'Trim Shop',   'Trim' },
    'LANSING-2:Body Shop'  => new String[]{ 'LANSING-2', 'Body Shop',   'Body' },
    'LANSING-2:Chassis'    => new String[]{ 'LANSING-2', 'Chassis',     'Chassis' }
};

for (String key : shopDefs.keySet()) {
    if (!shopByKey.containsKey(key)) {
        String[] def = shopDefs.get(key);
        GWB_Plant__c plant = plantByCode.get(def[0]);
        if (plant != null)
            shops.add(new GWB_Plant_Shop__c(Name=def[1], Plant__c=plant.Id,
                                            Shop_Type__c=def[2], Active__c=true));
    }
}
if (!shops.isEmpty()) {
    insert shops;
    for (GWB_Plant_Shop__c s : [SELECT Id, Name, Plant__r.Plant_Code__c FROM GWB_Plant_Shop__c]) {
        shopByKey.put(s.Plant__r.Plant_Code__c + ':' + s.Name, s);
    }
}
System.debug('[Seed] Shops ready: ' + shopByKey.keySet());

// ── 3. Plant Functions ───────────────────────────────────────────────────────
List<GWB_Plant_Function__c> funcs = new List<GWB_Plant_Function__c>();
Map<String, Id> funcByShopName = new Map<String, Id>();

for (GWB_Plant_Function__c f : [SELECT Id, Name, Plant_Shop__c FROM GWB_Plant_Function__c]) {
    funcByShopName.put(f.Plant_Shop__c + ':' + f.Name, f.Id);
}

List<Object[]> funcDefs = new List<Object[]>{
    new Object[]{ 'FLINT-1:Body Shop',   'Welding Station A',  'WLD-A',  5,  4, '3-Shift' },
    new Object[]{ 'FLINT-1:Body Shop',   'Panel Sub-Assembly', 'PNL-B',  3,  3, '2-Shift' },
    new Object[]{ 'FLINT-1:Paint Shop',  'Spray Zone 1',       'SPR-1',  4,  3, '2-Shift' },
    new Object[]{ 'WARREN-3:Trim Shop',  'Door Trim Line',     'DTL-1',  6,  5, '3-Shift' },
    new Object[]{ 'LANSING-2:Body Shop', 'Rocker Panel',       'RPL-1',  4,  4, '3-Shift' },
    new Object[]{ 'LANSING-2:Chassis',   'Frame Mount',        'FRM-2',  5,  3, '2-Shift' }
};

for (Object[] def : funcDefs) {
    GWB_Plant_Shop__c shop = shopByKey.get((String)def[0]);
    if (shop == null) continue;
    String fKey = shop.Id + ':' + (String)def[1];
    if (!funcByShopName.containsKey(fKey)) {
        funcs.add(new GWB_Plant_Function__c(
            Name               = (String)def[1],
            Station__c         = (String)def[2],
            Plant_Shop__c      = shop.Id,
            Auth_Positions__c  = (Decimal)def[3],
            Current_Headcount__c = (Decimal)def[4],
            Shift_Pattern__c   = (String)def[5],
            Active__c          = true
        ));
    }
}
if (!funcs.isEmpty()) {
    insert funcs;
    for (GWB_Plant_Function__c f : [SELECT Id, Name, Plant_Shop__c FROM GWB_Plant_Function__c]) {
        funcByShopName.put(f.Plant_Shop__c + ':' + f.Name, f.Id);
    }
}
System.debug('[Seed] Plant Functions ready: ' + funcs.size() + ' inserted');

// ── 4. Idea Library ──────────────────────────────────────────────────────────
List<GWB_Idea_Library__c> libs = new List<GWB_Idea_Library__c>();
Map<String, Id> libByName = new Map<String, Id>();

for (GWB_Idea_Library__c l : [SELECT Id, Name FROM GWB_Idea_Library__c]) {
    libByName.put(l.Name, l.Id);
}

List<Object[]> libDefs = new List<Object[]>{
    // Name, Category, SignalTypes (multi-select), FTEMin, FTEMax, Effort, Safety, Quality, Finance, Description
    new Object[]{
        'Auto-Replenishment Kanban', 'Material Flow',
        'Bin-Depletion;Low-Stock-Alert', 0.5, 1.5, 'Low',
        false, true, false,
        'Replace manual bin-checking with sensor-driven Kanban cards and auto-replenishment triggers.'
    },
    new Object[]{
        'AGV Line Supply', 'Material Flow',
        'Bin-Depletion;Conveyor-Stoppage', 1.0, 2.0, 'Medium',
        true, false, true,
        'Deploy autonomous guided vehicles to move parts from supermarket to line-side, eliminating water-spider routes.'
    },
    new Object[]{
        'Predictive Maintenance Scheduling', 'Equipment',
        'Equipment-Downtime;Conveyor-Stoppage', 0.3, 0.8, 'High',
        true, true, false,
        'Use vibration and temperature sensors to predict failures 48h in advance and pre-schedule maintenance windows.'
    },
    new Object[]{
        'Cross-Training Rotation Program', 'Workforce',
        'Bin-Depletion;Low-Stock-Alert;Equipment-Downtime', 0.5, 1.0, 'Low',
        false, false, false,
        'Cross-train operators on 2–3 adjacent stations to allow flexible coverage during absenteeism peaks.'
    },
    new Object[]{
        'Robotic Welding Cell Upgrade', 'Automation',
        'Equipment-Downtime;Conveyor-Stoppage', 1.5, 3.0, 'High',
        true, true, true,
        'Replace aging MIG welding stations with new 6-axis robotic cells achieving cycle-time reduction and quality improvement.'
    },
    new Object[]{
        'Vision-System Quality Gate', 'Quality',
        'Bin-Depletion;Low-Stock-Alert', 0.4, 0.8, 'Medium',
        false, true, false,
        'Install inline vision cameras to auto-detect panel gaps and mis-welds, reducing end-of-line rework.'
    }
};

for (Object[] def : libDefs) {
    if (!libByName.containsKey((String)def[0])) {
        libs.add(new GWB_Idea_Library__c(
            Name                     = (String)def[0],
            Idea_Category__c         = (String)def[1],
            Applicable_Signal_Types__c = (String)def[2],
            Typical_FTE_Min__c       = (Decimal)def[3],
            Typical_FTE_Max__c       = (Decimal)def[4],
            Typical_Effort__c        = (String)def[5],
            Requires_Safety_Review__c    = (Boolean)def[6],
            Requires_Quality_Review__c   = (Boolean)def[7],
            Requires_Finance_Approval__c = (Boolean)def[8],
            Description__c           = (String)def[9]
        ));
    }
}
if (!libs.isEmpty()) {
    insert libs;
    for (GWB_Idea_Library__c l : [SELECT Id, Name FROM GWB_Idea_Library__c]) {
        libByName.put(l.Name, l.Id);
    }
}
System.debug('[Seed] Idea Library ready: ' + libByName.keySet());

// ── 5. Plant Benchmarks ──────────────────────────────────────────────────────
List<GWB_Plant_Benchmark__c> benchmarks = new List<GWB_Plant_Benchmark__c>();

// Only insert if no benchmarks exist yet
if ([SELECT COUNT() FROM GWB_Plant_Benchmark__c] == 0) {
    Id kanbanId = libByName.get('Auto-Replenishment Kanban');
    Id agvId    = libByName.get('AGV Line Supply');
    Id xtrainId = libByName.get('Cross-Training Rotation Program');
    Id visionId = libByName.get('Vision-System Quality Gate');

    Id flint1   = plantByCode.get('FLINT-1')?.Id;
    Id warren3  = plantByCode.get('WARREN-3')?.Id;
    Id lansing2 = plantByCode.get('LANSING-2')?.Id;

    if (kanbanId != null && flint1 != null)
        benchmarks.add(new GWB_Plant_Benchmark__c(
            Name='FLINT-1 Kanban Q1', Idea_Library__c=kanbanId, Plant__c=flint1,
            Shop_Type__c='Body', Achieved_FTE__c=1.2, Quarter__c='2025-Q1',
            Production_Context__c='High-volume truck body panels',
            Notes__c='Eliminated 1.2 FTE water-spider runs on Weld Line A'
        ));
    if (kanbanId != null && warren3 != null)
        benchmarks.add(new GWB_Plant_Benchmark__c(
            Name='WARREN-3 Kanban Q2', Idea_Library__c=kanbanId, Plant__c=warren3,
            Shop_Type__c='Trim', Achieved_FTE__c=0.9, Quarter__c='2025-Q2',
            Production_Context__c='Mixed model trim assembly',
            Notes__c='Reduced line-side bin management by 0.9 FTE'
        ));
    if (agvId != null && lansing2 != null)
        benchmarks.add(new GWB_Plant_Benchmark__c(
            Name='LANSING-2 AGV Q3', Idea_Library__c=agvId, Plant__c=lansing2,
            Shop_Type__c='Body', Achieved_FTE__c=1.8, Quarter__c='2025-Q3',
            Production_Context__c='2-door crossover body shop',
            Notes__c='2 AGVs replaced 1.8 FTE water-spider routes over 2 shifts'
        ));
    if (xtrainId != null && flint1 != null)
        benchmarks.add(new GWB_Plant_Benchmark__c(
            Name='FLINT-1 CrossTrain Q2', Idea_Library__c=xtrainId, Plant__c=flint1,
            Shop_Type__c='Body', Achieved_FTE__c=0.7, Quarter__c='2025-Q2',
            Production_Context__c='High absenteeism weeks — 15% absence rate',
            Notes__c='Cross-training 4 operators reduced cover headcount by 0.7 FTE'
        ));
    if (visionId != null && warren3 != null)
        benchmarks.add(new GWB_Plant_Benchmark__c(
            Name='WARREN-3 Vision Q1', Idea_Library__c=visionId, Plant__c=warren3,
            Shop_Type__c='Trim', Achieved_FTE__c=0.5, Quarter__c='2025-Q1',
            Production_Context__c='Door trim inner panel inspection',
            Notes__c='Vision gate eliminated 0.5 FTE manual inspection on trim line'
        ));
    if (!benchmarks.isEmpty()) insert benchmarks;
}
System.debug('[Seed] Benchmarks ready: ' + benchmarks.size() + ' inserted');

// ── 6. HQ Targets ────────────────────────────────────────────────────────────
List<GWB_HQ_Target__c> targets = new List<GWB_HQ_Target__c>();

if ([SELECT COUNT() FROM GWB_HQ_Target__c] == 0) {
    GWB_Plant_Shop__c flintBody   = shopByKey.get('FLINT-1:Body Shop');
    GWB_Plant_Shop__c flintPaint  = shopByKey.get('FLINT-1:Paint Shop');
    GWB_Plant_Shop__c warrenTrim  = shopByKey.get('WARREN-3:Trim Shop');
    GWB_Plant_Shop__c lansingBody = shopByKey.get('LANSING-2:Body Shop');

    GWB_Plant__c flint1   = plantByCode.get('FLINT-1');
    GWB_Plant__c warren3  = plantByCode.get('WARREN-3');
    GWB_Plant__c lansing2 = plantByCode.get('LANSING-2');

    if (flintBody != null && flint1 != null)
        targets.add(new GWB_HQ_Target__c(
            Name='FLINT-1 Body 2025-Q3', Plant__c=flint1.Id, Plant_Shop__c=flintBody.Id,
            Quarter__c='2025-Q3', Target_FTE__c=2.0, Approved_FTE_Coverage__c=0.5,
            Production_Context__c='Truck body panel production — high volume, 3 shifts. ' +
                'Known bin depletion issue on Weld Line A causing 15-min stoppages twice per shift.'
        ));
    if (flintPaint != null && flint1 != null)
        targets.add(new GWB_HQ_Target__c(
            Name='FLINT-1 Paint 2025-Q3', Plant__c=flint1.Id, Plant_Shop__c=flintPaint.Id,
            Quarter__c='2025-Q3', Target_FTE__c=1.0, Approved_FTE_Coverage__c=0.0,
            Production_Context__c='Spray booth area — recently automated primer stage. ' +
                'Remaining manual touch-up team of 3 operators.'
        ));
    if (warrenTrim != null && warren3 != null)
        targets.add(new GWB_HQ_Target__c(
            Name='WARREN-3 Trim 2025-Q3', Plant__c=warren3.Id, Plant_Shop__c=warrenTrim.Id,
            Quarter__c='2025-Q3', Target_FTE__c=1.5, Approved_FTE_Coverage__c=0.9,
            Production_Context__c='Door trim assembly — mixed model. ' +
                'Quality escapes on inner door panel increasing rework time.'
        ));
    if (lansingBody != null && lansing2 != null)
        targets.add(new GWB_HQ_Target__c(
            Name='LANSING-2 Body 2025-Q3', Plant__c=lansing2.Id, Plant_Shop__c=lansingBody.Id,
            Quarter__c='2025-Q3', Target_FTE__c=2.5, Approved_FTE_Coverage__c=1.8,
            Production_Context__c='Crossover body shop — rocker panel and A-pillar sub-assembly. ' +
                'Recent AGV pilot delivered early FTE savings.'
        ));
    if (!targets.isEmpty()) insert targets;
}
System.debug('[Seed] HQ Targets ready: ' + targets.size() + ' inserted');

// ── 7. Edge Signals ──────────────────────────────────────────────────────────
List<GWB_Edge_Signal__c> signals = new List<GWB_Edge_Signal__c>();

if ([SELECT COUNT() FROM GWB_Edge_Signal__c] == 0) {
    // Need Plant Function IDs for signals
    Map<String, Id> funcIdByStation = new Map<String, Id>();
    for (GWB_Plant_Function__c f : [SELECT Id, Station__c FROM GWB_Plant_Function__c]) {
        funcIdByStation.put(f.Station__c, f.Id);
    }

    if (funcIdByStation.containsKey('WLD-A'))
        signals.add(new GWB_Edge_Signal__c(
            Station__c='WLD-A', Signal_Type__c='Bin-Depletion',
            Risk__c='High', Current_Level__c=12, Minutes_To_Empty__c=18,
            Plant_Function__c=funcIdByStation.get('WLD-A'), Processed__c=false,
            Raw_JSON__c='{"station":"WLD-A","signal_type":"Bin-Depletion","current_level":12,"minutes_to_empty":18,"risk":"High","plant_code":"FLINT-1"}'
        ));
    if (funcIdByStation.containsKey('SPR-1'))
        signals.add(new GWB_Edge_Signal__c(
            Station__c='SPR-1', Signal_Type__c='Low-Stock-Alert',
            Risk__c='Medium', Current_Level__c=30, Minutes_To_Empty__c=45,
            Plant_Function__c=funcIdByStation.get('SPR-1'), Processed__c=false,
            Raw_JSON__c='{"station":"SPR-1","signal_type":"Low-Stock-Alert","current_level":30,"minutes_to_empty":45,"risk":"Medium","plant_code":"FLINT-1"}'
        ));
    if (funcIdByStation.containsKey('DTL-1'))
        signals.add(new GWB_Edge_Signal__c(
            Station__c='DTL-1', Signal_Type__c='Equipment-Downtime',
            Risk__c='High', Current_Level__c=0, Minutes_To_Empty__c=0,
            Plant_Function__c=funcIdByStation.get('DTL-1'), Processed__c=false,
            Raw_JSON__c='{"station":"DTL-1","signal_type":"Equipment-Downtime","current_level":0,"minutes_to_empty":0,"risk":"High","plant_code":"WARREN-3"}'
        ));
    if (!signals.isEmpty()) insert signals;
}
System.debug('[Seed] Edge Signals ready: ' + signals.size() + ' inserted');

System.debug('[Seed] ✅ All seed data complete.');
