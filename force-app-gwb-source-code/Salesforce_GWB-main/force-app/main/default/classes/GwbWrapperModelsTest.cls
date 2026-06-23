@isTest
private class GwbWrapperModelsTest {
    @isTest
    static void constructorsSetExpectedDefaults() {
        OperationWrapper operation = new OperationWrapper();
        System.assertEquals(0, operation.crew1, 'Crew 1 should default to zero.');
        System.assertEquals(0, operation.crew2, 'Crew 2 should default to zero.');
        System.assertEquals(0, operation.crew3, 'Crew 3 should default to zero.');
        System.assertEquals(0, operation.total, 'Total should default to zero.');

        GwbFunctionWrapper functionWrapper = new GwbFunctionWrapper();
        System.assertEquals(1, functionWrapper.crewEditableCount, 'Editable crew count should default to one.');
        System.assertEquals(0, functionWrapper.crew1, 'Crew 1 should default to zero.');
        System.assertEquals(0, functionWrapper.crew2, 'Crew 2 should default to zero.');
        System.assertEquals(0, functionWrapper.crew3, 'Crew 3 should default to zero.');
        System.assertEquals(0, functionWrapper.actualTotal, 'Actual total should default to zero.');
        System.assertEquals(0, functionWrapper.total, 'Total should default to zero.');
        System.assertEquals(true, functionWrapper.editable, 'Wrapper should default to editable.');
        System.assertEquals(false, functionWrapper.hasActiveOperations, 'Wrapper should default to no active operations.');
        System.assertNotEquals(null, functionWrapper.operations, 'Operations list should always be initialized.');
        System.assertEquals(0, functionWrapper.operations.size(), 'Operations list should start empty.');

        InitiativeSectionWrapper section = new InitiativeSectionWrapper();
        System.assertEquals(true, section.editable, 'Section should default to editable.');
        System.assertEquals(0, section.totalAdjustments, 'Section totals should default to zero.');
        System.assertEquals(0, section.initiativePositionAdjustment, 'Section position adjustment should default to zero.');
        System.assertEquals(false, section.hasParentInitiative, 'Parent flag should default to false.');
        System.assertEquals(false, section.isContainmentDriver, 'Containment flag should default to false.');
        System.assertEquals(true, section.addFunctionsAllowed, 'Add-functions flag should default to true.');
        System.assertNotEquals(null, section.gwbFunctions, 'Function list should always be initialized.');
        System.assertEquals(0, section.gwbFunctions.size(), 'Function list should start empty.');

        SaveRequestWrapper request = new SaveRequestWrapper();
        System.assertNotEquals(null, request.sections, 'Sections should be initialized.');
        System.assertEquals(0, request.sections.size(), 'Sections should start empty.');
    }

    @isTest
    static void nestedAssignmentsCanBePersistedInMemory() {
        OperationWrapper operation = new OperationWrapper();
        operation.crew1 = 1;
        operation.crew2 = 2;
        operation.crew3 = 3;
        operation.total = operation.crew1 + operation.crew2 + operation.crew3;

        GwbFunctionWrapper functionWrapper = new GwbFunctionWrapper();
        functionWrapper.operations.add(operation);
        functionWrapper.crew1 = 1;
        functionWrapper.crew2 = 2;
        functionWrapper.crew3 = 3;
        functionWrapper.total = 6;

        InitiativeSectionWrapper section = new InitiativeSectionWrapper();
        section.gwbFunctions.add(functionWrapper);
        section.totalAdjustments = 6;

        SaveRequestWrapper request = new SaveRequestWrapper();
        request.sections.add(section);

        System.assertEquals(1, request.sections.size(), 'One section should be present.');
        System.assertEquals(1, request.sections[0].gwbFunctions.size(), 'One function row should be present.');
        System.assertEquals(1, request.sections[0].gwbFunctions[0].operations.size(), 'One operation row should be present.');
        System.assertEquals(6, request.sections[0].gwbFunctions[0].operations[0].total, 'Operation total should reflect assigned values.');
    }
}