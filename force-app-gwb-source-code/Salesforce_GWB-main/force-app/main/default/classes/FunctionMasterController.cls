/**
 * Controller for Function Master Related List LWC
 * 
 */
public with sharing class FunctionMasterController {
	/**
     * Get current year position values
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPlantProgramData(Id functionId) {

        List<Plant_Function__c> pfList = [
            SELECT Id, Name,
                   Plant_Program__r.Id,
                   Plant_Program__r.Name,
                   Plant_Program__r.Plant_Program_Name__c,
                   Plant_Program__r.RecordType.DeveloperName
            FROM Plant_Function__c
            WHERE Function__c = :functionId
        ];
        
        Integer currentYear = Date.today().year();
        Integer currentMonth = Date.today().month();

        Set<Id> plantProgramIds = new Set<Id>();
        Set<Id> plantFunctionIds = new Set<Id>();

        for (Plant_Function__c pf : pfList) {
            plantProgramIds.add(pf.Plant_Program__r.Id);
            plantFunctionIds.add(pf.Id);
        }
        
        // Query Workbook
        List<Workbook__c> wbList = [
            SELECT Plant_Function__c,
                   Year__c,
                   Jan_Total__c, Feb_Total__c, Mar_Total__c, Apr_Total__c,
                   May_Total__c, Jun_Total__c, Jul_Total__c, Aug_Total__c,
                   Sep_Total__c, Oct_Total__c, Nov_Total__c, Dec_Total__c
            FROM Workbook__c
            WHERE Plant_Function__c IN :plantFunctionIds
            AND Year__c = :currentYear
        ];
        
        // Map: ProgramId + PFId → Positions
        Map<String, Decimal> workbookMap = new Map<String, Decimal>();

        for (Workbook__c wb : wbList) {

            String key = wb.Plant_Function__c;

            Decimal total = 0;

            if (currentMonth <= 1) total += (wb.Jan_Total__c != null ? wb.Jan_Total__c : 0);
            if (currentMonth <= 2) total += (wb.Feb_Total__c != null ? wb.Feb_Total__c : 0);
            if (currentMonth <= 3) total += (wb.Mar_Total__c != null ? wb.Mar_Total__c : 0);
            if (currentMonth <= 4) total += (wb.Apr_Total__c != null ? wb.Apr_Total__c : 0);
            if (currentMonth <= 5) total += (wb.May_Total__c != null ? wb.May_Total__c : 0);
            if (currentMonth <= 6) total += (wb.Jun_Total__c != null ? wb.Jun_Total__c : 0);
            if (currentMonth <= 7) total += (wb.Jul_Total__c != null ? wb.Jul_Total__c : 0);
            if (currentMonth <= 8) total += (wb.Aug_Total__c != null ? wb.Aug_Total__c : 0);
            if (currentMonth <= 9) total += (wb.Sep_Total__c != null ? wb.Sep_Total__c : 0);
            if (currentMonth <= 10) total += (wb.Oct_Total__c != null ? wb.Oct_Total__c : 0);
            if (currentMonth <= 11) total += (wb.Nov_Total__c != null ? wb.Nov_Total__c : 0);
            if (currentMonth <= 12) total += (wb.Dec_Total__c != null ? wb.Dec_Total__c : 0);

            workbookMap.put(key, total);
        }

        // Group: RecordType → Program → List of Plant Functions
        Map<String, Map<Id, List<Plant_Function__c>>> groupedData =
            new Map<String, Map<Id, List<Plant_Function__c>>>();

        for (Plant_Function__c pf : pfList) {

            String recordType = pf.Plant_Program__r.RecordType.DeveloperName;

            if (!groupedData.containsKey(recordType)) {
                groupedData.put(recordType, new Map<Id, List<Plant_Function__c>>());
            }

            Map<Id, List<Plant_Function__c>> programMap = groupedData.get(recordType);

            if (!programMap.containsKey(pf.Plant_Program__r.Id)) {
                programMap.put(pf.Plant_Program__r.Id, new List<Plant_Function__c>());
            }

            programMap.get(pf.Plant_Program__r.Id).add(pf);
        }

        // Prepare response
        Map<String, Object> result = new Map<String, Object>();

        for (String rt : groupedData.keySet()) {

            List<Object> programList = new List<Object>();

            for (Id progId : groupedData.get(rt).keySet()) {

                List<Plant_Function__c> pfRecords = groupedData.get(rt).get(progId);

                Map<String, Object> programObj = new Map<String, Object>();

                programObj.put('programId', progId);

                String programName = pfRecords[0].Plant_Program__r.Plant_Program_Name__c;
                if (String.isBlank(programName)) {
                    programName = pfRecords[0].Plant_Program__r.Name;
                }

                programObj.put('programName', programName);
                
                Decimal programTotal = 0;
                
                for (Plant_Function__c pf : pfRecords) {
                    String key = pf.Plant_Program__r.Id + '-' + pf.Id;

                    if (workbookMap.containsKey(key)) {
                        programTotal += workbookMap.get(key);
                    }
                }

                programObj.put('positions', programTotal);
                programObj.put('programUrl', '/' + progId);

                programList.add(programObj);
            }

            result.put(rt, new Map<String, Object>{
                'programCount' => groupedData.get(rt).size(),
                'programs' => programList
            });
        }

        return result;
    }
}