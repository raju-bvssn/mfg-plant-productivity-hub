/**
 * @description Handler for Operation_Plan__c trigger
 * Prevents duplicate combinations of Shifts_Numeric__c, Crews_Numeric__c, and Days__c
 */
public class OperationPlanTriggerHandler {
    
    /**
     * @description Main handler method
     */
    public static void handleTrigger(List<Operation_Plan__c> newRecords, Map<Id, Operation_Plan__c> oldMap) {
        // Collect all unique combinations from new records
        Set<String> combinationKeys = new Set<String>();
        Map<String, Operation_Plan__c> keyToRecordMap = new Map<String, Operation_Plan__c>();
        
        for (Operation_Plan__c op : newRecords) {
            // Skip if any of the required fields are null
            if (op.Shifts_Numeric__c == null || op.Crews_Numeric__c == null || op.Days__c == null) {
                continue;
            }
            
            // Create a unique key for the combination
            String combinationKey = String.valueOf(op.Shifts_Numeric__c) + '|' + 
                                   String.valueOf(op.Crews_Numeric__c) + '|' + 
                                   String.valueOf(op.Days__c);
            
            // Check for duplicates within the same transaction
            if (combinationKeys.contains(combinationKey)) {
                op.addError('This combination of Shifts, Crews and Days already exists in this transaction');
                continue;
            }
            
            combinationKeys.add(combinationKey);
            keyToRecordMap.put(combinationKey, op);
        }
        
        if (combinationKeys.isEmpty()) {
            return;
        }
        
        // Query for existing records with the same combinations
        // Exclude records being updated (if this is an update operation)
        Set<Id> excludeIds = new Set<Id>();
        if (oldMap != null) {
            for (Operation_Plan__c op : newRecords) {
                Operation_Plan__c oldOp = oldMap.get(op.Id);
                if (oldOp != null) {
                    // If the combination hasn't changed, exclude this record from the duplicate check
                    if (op.Shifts_Numeric__c == oldOp.Shifts_Numeric__c &&
                        op.Crews_Numeric__c == oldOp.Crews_Numeric__c &&
                        op.Days__c == oldOp.Days__c) {
                        excludeIds.add(op.Id);
                    }
                }
            }
        }
        
        // Collect all unique values for each field to build efficient query
        Set<Decimal> shiftsValues = new Set<Decimal>();
        Set<Decimal> crewsValues = new Set<Decimal>();
        Set<Decimal> daysValues = new Set<Decimal>();
        
        for (String key : combinationKeys) {
            List<String> parts = key.split('\\|');
            shiftsValues.add(Decimal.valueOf(parts[0]));
            crewsValues.add(Decimal.valueOf(parts[1]));
            daysValues.add(Decimal.valueOf(parts[2]));
        }
        
        // Query for existing records that might match (using IN clauses for efficiency)
        // Then filter in Apex to match exact combinations
        List<Operation_Plan__c> existingRecords = [
            SELECT Id, Shifts_Numeric__c, Crews_Numeric__c, Days__c
            FROM Operation_Plan__c
            WHERE Shifts_Numeric__c IN :shiftsValues
            AND Crews_Numeric__c IN :crewsValues
            AND Days__c IN :daysValues
            AND Id NOT IN :excludeIds
        ];
        
        // Create a map of existing combinations (filter for exact matches only)
        Map<String, Operation_Plan__c> existingCombinations = new Map<String, Operation_Plan__c>();
        for (Operation_Plan__c existing : existingRecords) {
            if (existing.Shifts_Numeric__c != null && 
                existing.Crews_Numeric__c != null && 
                existing.Days__c != null) {
                String existingKey = String.valueOf(existing.Shifts_Numeric__c) + '|' + 
                                   String.valueOf(existing.Crews_Numeric__c) + '|' + 
                                   String.valueOf(existing.Days__c);
                
                // Only add if it matches one of the combinations we're checking
                if (combinationKeys.contains(existingKey)) {
                    existingCombinations.put(existingKey, existing);
                }
            }
        }
        
        // Add errors to records with duplicate combinations
        for (String key : combinationKeys) {
            if (existingCombinations.containsKey(key)) {
                Operation_Plan__c duplicateRecord = keyToRecordMap.get(key);
                if (duplicateRecord != null) {
                    duplicateRecord.addError('This combination of Shifts, Crews and Days already exists');
                }
            }
        }
    }
}