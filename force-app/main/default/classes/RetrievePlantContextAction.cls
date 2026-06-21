public with sharing class RetrievePlantContextAction {

    public class PlantContext {
        @InvocableVariable(label='Target ID')
        public Id targetId;
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
        @InvocableVariable(label='Plant Function ID')
        public Id plantFunctionId;
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
        @InvocableVariable(label='Recent Signal Type')
        public String recentSignalType;
    }

    @InvocableMethod(label='Retrieve Plant Context' description='Given an HQ Target ID, returns plant/shop/target context for Agentforce')
    public static List<PlantContext> getContext(List<Id> targetIds) {
        List<PlantContext> results = new List<PlantContext>();
        for (Id targetId : targetIds) {
            results.add(buildContext(targetId));
        }
        return results;
    }

    private static PlantContext buildContext(Id targetId) {
        PlantContext ctx = new PlantContext();
        ctx.targetId = targetId;

        List<GWB_HQ_Target__c> targets = [
            SELECT Id, Target_FTE__c, Approved_FTE_Coverage__c, Gap_To_Target__c,
                   Production_Context__c, Quarter__c,
                   Plant_Shop__c,
                   Plant_Shop__r.Name,
                   Plant_Shop__r.Shop_Type__c,
                   Plant_Shop__r.Plant__c,
                   Plant_Shop__r.Plant__r.Name,
                   Plant_Shop__r.Plant__r.Plant_Code__c
            FROM GWB_HQ_Target__c
            WHERE Id = :targetId
            LIMIT 1
        ];
        if (targets.isEmpty()) return ctx;

        GWB_HQ_Target__c t = targets[0];
        ctx.targetFTE           = t.Target_FTE__c;
        ctx.approvedFTECoverage = t.Approved_FTE_Coverage__c;
        ctx.gapToTarget         = t.Gap_To_Target__c;
        ctx.productionContext   = t.Production_Context__c;
        ctx.quarter             = t.Quarter__c;
        ctx.shopName            = t.Plant_Shop__r.Name;
        ctx.shopType            = t.Plant_Shop__r.Shop_Type__c;
        ctx.plantName           = t.Plant_Shop__r.Plant__r.Name;
        ctx.plantCode           = t.Plant_Shop__r.Plant__r.Plant_Code__c;

        // Get the first active plant function for this shop (for idea linkage)
        List<GWB_Plant_Function__c> functions = [
            SELECT Id, Name, Auth_Positions__c, Current_Headcount__c
            FROM GWB_Plant_Function__c
            WHERE Plant_Shop__c = :t.Plant_Shop__c
            AND Active__c = true
            ORDER BY Name ASC
            LIMIT 1
        ];
        if (!functions.isEmpty()) {
            ctx.plantFunctionId  = functions[0].Id;
            ctx.functionName     = functions[0].Name;
            ctx.authPositions    = functions[0].Auth_Positions__c;
            ctx.currentHeadcount = functions[0].Current_Headcount__c;
        }

        // Enrich with most recent edge signal type from this shop's functions
        Set<Id> shopFunctionIds = new Set<Id>();
        for (GWB_Plant_Function__c fn : [
            SELECT Id FROM GWB_Plant_Function__c WHERE Plant_Shop__c = :t.Plant_Shop__c
        ]) {
            shopFunctionIds.add(fn.Id);
        }

        if (!shopFunctionIds.isEmpty()) {
            List<GWB_Edge_Signal__c> recentSignals = [
                SELECT Signal_Type__c
                FROM GWB_Edge_Signal__c
                WHERE Plant_Function__c IN :shopFunctionIds
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            ctx.recentSignalType = !recentSignals.isEmpty()
                ? recentSignals[0].Signal_Type__c
                : 'Bin-Depletion';
        } else {
            ctx.recentSignalType = 'Bin-Depletion';
        }

        return ctx;
    }
}
