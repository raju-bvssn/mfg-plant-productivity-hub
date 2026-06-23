/**
 * @description Test class for OperationPlanTriggerHandler
 */
@isTest
private class OperationPlanTriggerHandlerTest {

    @isTest
    static void testInsertUniqueCombination() {
        Operation_Plan__c op = new Operation_Plan__c(
            Shifts_Numeric__c = 2,
            Crews_Numeric__c = 1,
            Days__c = 5
        );
        Test.startTest();
        insert op;
        Test.stopTest();
        System.assertNotEquals(null, op.Id);
    }

    @isTest
    static void testInsertDuplicateCombination() {
        Operation_Plan__c op1 = new Operation_Plan__c(
            Shifts_Numeric__c = 2,
            Crews_Numeric__c = 1,
            Days__c = 5
        );
        insert op1;

        Operation_Plan__c op2 = new Operation_Plan__c(
            Shifts_Numeric__c = 2,
            Crews_Numeric__c = 1,
            Days__c = 5
        );
        Boolean thrown = false;
        try {
            insert op2;
        } catch (DmlException e) {
            thrown = true;
            System.assert(e.getMessage().contains('already exists'));
        }
        System.assertEquals(true, thrown, 'Should throw for duplicate combination');
    }

    @isTest
    static void testUpdateSameCombination() {
        Operation_Plan__c op = new Operation_Plan__c(
            Shifts_Numeric__c = 2,
            Crews_Numeric__c = 1,
            Days__c = 5
        );
        insert op;

        op.Name = 'Updated Name';
        Test.startTest();
        update op;
        Test.stopTest();
        System.assertNotEquals(null, op.Id);
    }

    @isTest
    static void testInsertWithNullFields() {
        Operation_Plan__c op = new Operation_Plan__c(
            Shifts_Numeric__c = 2,
            Crews_Numeric__c = null,
            Days__c = 5
        );
        Test.startTest();
        insert op;
        Test.stopTest();
        System.assertNotEquals(null, op.Id);
    }

    @isTest
    static void testInsertDuplicateWithinTransaction() {
        List<Operation_Plan__c> ops = new List<Operation_Plan__c>{
            new Operation_Plan__c(Shifts_Numeric__c = 3, Crews_Numeric__c = 2, Days__c = 5),
            new Operation_Plan__c(Shifts_Numeric__c = 3, Crews_Numeric__c = 2, Days__c = 5)
        };
        Boolean thrown = false;
        try {
            insert ops;
        } catch (DmlException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Should throw for duplicate within same transaction');
    }
}