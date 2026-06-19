public with sharing class RetrievePlantContextAction {

    public class PlantContext {
        @InvocableVariable(label='Signal ID')
        public Id signalId;
        @InvocableVariable(label='Plant Name')
        public String plantName;
        @InvocableVariable(label='Plant Code')
        public String plantCode;
        @InvocableVariable(label='Shop Name')
        public String shopName;
        @InvocableVariable(label='Shop Type')
        public String shopType;
        @InvocableVariable(label='Function Name')
        public String functionName;
        @InvocableVariable(label='Station')
        public String station;
        @InvocableVariable(label='Auth Positions')
        public Decimal authPositions;
        @InvocableVariable(label='Current Headcount')
        public Decimal currentHeadcount;
        @InvocableVariable(label='HQ Target FTE')
        public Decimal targetFTE;
        @InvocableVariable(label='Approved FTE Coverage')
        public Decimal approvedFTECoverage;
        @InvocableVariable(label='Gap To Target')
        public Decimal gapToTarget;
        @InvocableVariable(label='Production Context')
        public String productionContext;
        @InvocableVariable(label='Quarter')
        public String quarter;
        @InvocableVariable(label='Signal Type')
        public String signalType;
        @InvocableVariable(label='Risk Level')
        public String riskLevel;
    }

    @InvocableMethod(label='Retrieve Plant Context' description='Given an Edge Signal ID, returns plant/shop/target context for Agentforce')
    public static List<PlantContext> getContext(List<Id> signalIds) {
        List<PlantContext> results = new List<PlantContext>();
        for (Id sigId : signalIds) {
            results.add(buildContext(sigId));
        }
        return results;
    }

    private static PlantContext buildContext(Id sigId) {
        PlantContext ctx = new PlantContext();
        ctx.signalId = sigId;

        List<GWB_Edge_Signal__c> sigs = [
            SELECT Id, Station__c, Signal_Type__c, Risk__c, Plant_Function__c,
                   Plant_Function__r.Name, Plant_Function__r.Auth_Positions__c,
                   Plant_Function__r.Current_Headcount__c,
                   Plant_Function__r.Plant_Shop__c,
                   Plant_Function__r.Plant_Shop__r.Name,
                   Plant_Function__r.Plant_Shop__r.Shop_Type__c,
                   Plant_Function__r.Plant_Shop__r.Plant__c,
                   Plant_Function__r.Plant_Shop__r.Plant__r.Name,
                   Plant_Function__r.Plant_Shop__r.Plant__r.Plant_Code__c
            FROM GWB_Edge_Signal__c
            WHERE Id = :sigId
            LIMIT 1
        ];
        if (sigs.isEmpty()) return ctx;

        GWB_Edge_Signal__c sig = sigs[0];
        ctx.station    = sig.Station__c;
        ctx.signalType = sig.Signal_Type__c;
        ctx.riskLevel  = sig.Risk__c;

        if (sig.Plant_Function__c != null) {
            ctx.functionName      = sig.Plant_Function__r.Name;
            ctx.authPositions     = sig.Plant_Function__r.Auth_Positions__c;
            ctx.currentHeadcount  = sig.Plant_Function__r.Current_Headcount__c;
            ctx.shopName          = sig.Plant_Function__r.Plant_Shop__r.Name;
            ctx.shopType          = sig.Plant_Function__r.Plant_Shop__r.Shop_Type__c;
            ctx.plantName         = sig.Plant_Function__r.Plant_Shop__r.Plant__r.Name;
            ctx.plantCode         = sig.Plant_Function__r.Plant_Shop__r.Plant__r.Plant_Code__c;

            List<GWB_HQ_Target__c> targets = [
                SELECT Id, Target_FTE__c, Approved_FTE_Coverage__c, Gap_To_Target__c,
                       Production_Context__c, Quarter__c
                FROM GWB_HQ_Target__c
                WHERE Plant_Shop__c = :sig.Plant_Function__r.Plant_Shop__c
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!targets.isEmpty()) {
                GWB_HQ_Target__c t = targets[0];
                ctx.targetFTE           = t.Target_FTE__c;
                ctx.approvedFTECoverage = t.Approved_FTE_Coverage__c;
                ctx.gapToTarget         = t.Gap_To_Target__c;
                ctx.productionContext   = t.Production_Context__c;
                ctx.quarter             = t.Quarter__c;
            }
        }
        return ctx;
    }
}
