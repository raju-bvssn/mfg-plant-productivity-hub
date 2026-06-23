public with sharing class PPS_TestDataFactory {
    public class DemoData {
        public Plant__c plant;
        public Operation_Plan__c oneCrewPlan;
        public Operation_Plan__c twoCrewPlan;
        public Operation_Plan__c threeCrewPlan;
        public Plant_Program__c plantProgram;
        public Function__c functionOne;
        public Function__c functionTwo;
        public Plant_Function__c plantFunctionOne;
        public Plant_Function__c plantFunctionTwo;
        public Operation__c operationOne;
        public Operation__c operationTwo;
        public Initiative__c permanentInitiative;
        public Initiative__c temporaryInitiative;
        public Initiative__c containmentParentInitiative;
        public Initiative__c containmentChildInitiative;
    }

    public static DemoData createDemoData() {
        DemoData data = new DemoData();
        String suffix = String.valueOf(DateTime.now().getTime());

        data.plant = new Plant__c(
            Name = 'PPS Test Plant ' + suffix,
            Auth_Region__c = 'GMNA',
            MVP__c = 'PPS',
            Status__c = 'Active'
        );
        insert data.plant;

        data.oneCrewPlan = getOrCreateOperationPlan('PPS 1 Crew ' + suffix, 1);
        data.twoCrewPlan = getOrCreateOperationPlan('PPS 2 Crew ' + suffix, 2);
        data.threeCrewPlan = getOrCreateOperationPlan('PPS 3 Crew ' + suffix, 3);

        data.plantProgram = new Plant_Program__c(
            Auth_Plant_Name__c = data.plant.Id,
            Program_Product_Index__c = 'A',
            Program_Code__c = 'CSS',
            Include__c = true,
            Shifts_Def__c = data.twoCrewPlan.Id
        );
        insert data.plantProgram;

        data.functionOne = createFunction('Function Master Name 1');
        data.functionTwo = createFunction('Function Master Name 2');
        insert new List<Function__c>{ data.functionOne, data.functionTwo };

        data.plantFunctionOne = createPlantFunction(
            data.functionOne.Id,
            data.plant.Id,
            data.plantProgram.Id,
            data.threeCrewPlan.Id,
            'Function Master Name 1',
            'GA',
            suffix + '-1'
        );
        data.plantFunctionTwo = createPlantFunction(
            data.functionTwo.Id,
            data.plant.Id,
            data.plantProgram.Id,
            null,
            'Function Master Name 2',
            'GA',
            suffix + '-2'
        );
        insert new List<Plant_Function__c>{ data.plantFunctionOne, data.plantFunctionTwo };

        data.operationOne = createOperation(data.plant.Id, data.plantFunctionOne.Id, '1AEST', 'GA');
        data.operationTwo = createOperation(data.plant.Id, data.plantFunctionOne.Id, '1BEST', 'GA');
        insert new List<Operation__c>{ data.operationOne, data.operationTwo };

        data.permanentInitiative = createInitiative(data.plant.Id, 'Permanent', Date.newInstance(2026, 3, 5), null, 5);
        data.temporaryInitiative = createInitiative(data.plant.Id, 'Permanent', Date.newInstance(2026, 6, 5), null, 5);
        data.containmentParentInitiative = createInitiative(data.plant.Id, 'Permanent', Date.newInstance(2026, 5, 5), Date.newInstance(2026, 8, 5), 6);
        data.containmentParentInitiative.Driver__c = 'Containment';
        insert new List<Initiative__c>{ data.permanentInitiative, data.temporaryInitiative, data.containmentParentInitiative };

        data.containmentChildInitiative = createInitiative(data.plant.Id, 'Permanent', Date.newInstance(2026, 6, 5), Date.newInstance(2026, 8, 5), 6);
        data.containmentChildInitiative.Driver__c = 'Containment';
        data.containmentChildInitiative.Parent_Initiative__c = data.containmentParentInitiative.Id;
        insert data.containmentChildInitiative;

        return data;
    }

    public static void seedBackendSampleData() {
        DemoData data = createDemoData();
        data.permanentInitiative.Position_Adjustment__c = 6;
        data.temporaryInitiative.Position_Adjustment__c = 6;
        data.containmentParentInitiative.Position_Adjustment__c = 6;
        data.containmentChildInitiative.Position_Adjustment__c = 6;
        update new List<Initiative__c>{
            data.permanentInitiative,
            data.temporaryInitiative,
            data.containmentParentInitiative,
            data.containmentChildInitiative
        };

        Function__c oneCrewFunction = createFunction('Function Master Name 3');
        insert oneCrewFunction;
        Plant_Function__c oneCrewPlantFunction = createPlantFunction(
            oneCrewFunction.Id,
            data.plant.Id,
            data.plantProgram.Id,
            data.oneCrewPlan.Id,
            'Function Master Name 3',
            'GA',
            DateTime.now().getTime() + '-seed-one-crew'
        );
        insert oneCrewPlantFunction;

        Operation__c operationThree = createOperation(data.plant.Id, data.plantFunctionOne.Id, '14DBE', 'DOLLY TRAIN LH CLOSURES', 'TUGGER', 'GROUP 2', 'GA');
        Operation__c operationFour = createOperation(data.plant.Id, data.plantFunctionTwo.Id, '21DBE', 'DOLLY TRAIN LH CLOSURES', 'TUGGER', 'GROUP 2', 'GA');
        Operation__c operationFive = createOperation(data.plant.Id, oneCrewPlantFunction.Id, '31DBE', 'DOLLY TRAIN', 'TUGGER', 'GROUP 1', 'GA');
        insert new List<Operation__c>{ operationThree, operationFour, operationFive };

        List<Plant_Function__c> extraPlantFunctions = createAdditionalPlantFunctions(data, DateTime.now().getTime());
        insert extraPlantFunctions;
        insert createAdditionalOperations(data, extraPlantFunctions);

        List<InitiativeSectionWrapper> forecastSections = new List<InitiativeSectionWrapper>{
            createSection('effective', 'Effective Date', 2026, 'Mar', true, new List<Plant_Function__c>{ data.plantFunctionOne, data.plantFunctionTwo, oneCrewPlantFunction })
        };
        forecastSections[0].gwbFunctions[0].crew1 = 1;
        forecastSections[0].gwbFunctions[0].crew2 = 1;
        forecastSections[0].gwbFunctions[0].crew3 = 1;
        forecastSections[0].gwbFunctions[1].crew1 = 1;
        forecastSections[0].gwbFunctions[1].crew2 = 1;
        forecastSections[0].gwbFunctions[1].crew3 = 0;
        forecastSections[0].gwbFunctions[2].crew1 = 1;
        forecastSections[0].gwbFunctions[2].crew2 = 0;
        forecastSections[0].gwbFunctions[2].crew3 = 0;

        InitiativeDetailService.saveForecastData(data.permanentInitiative.Id, JSON.serialize(new SaveRequestWrapperWithSections(forecastSections)));

        List<InitiativeSectionWrapper> actualSections = new List<InitiativeSectionWrapper>{
            createSection('effective', 'Effective Date', 2026, 'Mar', true, new List<Plant_Function__c>{ data.plantFunctionOne, data.plantFunctionTwo, oneCrewPlantFunction })
        };
        actualSections[0].gwbFunctions[0].operations.add(createOperationWrapper(data.operationOne.Id, '1AEST', 1, 0, 1));
        actualSections[0].gwbFunctions[0].operations.add(createOperationWrapper(data.operationTwo.Id, '1BEST', 0, 1, 0));
        actualSections[0].gwbFunctions[0].operations.add(createOperationWrapper(operationThree.Id, '14DBE', 0, 0, 0));
        actualSections[0].gwbFunctions[1].operations.add(createOperationWrapper(operationFour.Id, '21DBE', 1, 1, 0));
        actualSections[0].gwbFunctions[2].operations.add(createOperationWrapper(operationFive.Id, '31DBE', 1, 0, 0));
        InitiativeDetailService.saveActualData(data.permanentInitiative.Id, JSON.serialize(new SaveRequestWrapperWithSections(actualSections)));

        seedInitiativeRows(data.temporaryInitiative.Id, 2026, 'June', data, oneCrewPlantFunction, operationThree, operationFour, operationFive);
        seedInitiativeRows(data.containmentParentInitiative.Id, 2026, 'May', data, oneCrewPlantFunction, operationThree, operationFour, operationFive);
        seedInitiativeRows(data.containmentChildInitiative.Id, 2026, 'June', data, oneCrewPlantFunction, operationThree, operationFour, operationFive);
    }

    private static void seedInitiativeRows(
        Id initiativeId,
        Integer year,
        String month,
        DemoData data,
        Plant_Function__c oneCrewPlantFunction,
        Operation__c operationThree,
        Operation__c operationFour,
        Operation__c operationFive
    ) {
        List<InitiativeSectionWrapper> forecastSections = new List<InitiativeSectionWrapper>{
            createSection('effective', 'Effective Date', year, month, true, new List<Plant_Function__c>{ data.plantFunctionOne, data.plantFunctionTwo, oneCrewPlantFunction })
        };
        forecastSections[0].gwbFunctions[0].crew1 = 1;
        forecastSections[0].gwbFunctions[0].crew2 = 1;
        forecastSections[0].gwbFunctions[0].crew3 = 1;
        forecastSections[0].gwbFunctions[1].crew1 = 1;
        forecastSections[0].gwbFunctions[1].crew2 = 1;
        forecastSections[0].gwbFunctions[1].crew3 = 0;
        forecastSections[0].gwbFunctions[2].crew1 = 1;
        forecastSections[0].gwbFunctions[2].crew2 = 0;
        forecastSections[0].gwbFunctions[2].crew3 = 0;
        InitiativeDetailService.saveForecastData(initiativeId, JSON.serialize(new SaveRequestWrapperWithSections(forecastSections)));

        List<InitiativeSectionWrapper> actualSections = new List<InitiativeSectionWrapper>{
            createSection('effective', 'Effective Date', year, month, true, new List<Plant_Function__c>{ data.plantFunctionOne, data.plantFunctionTwo, oneCrewPlantFunction })
        };
        actualSections[0].gwbFunctions[0].operations.add(createOperationWrapper(data.operationOne.Id, '1AEST', 1, 0, 1));
        actualSections[0].gwbFunctions[0].operations.add(createOperationWrapper(data.operationTwo.Id, '1BEST', 0, 1, 0));
        actualSections[0].gwbFunctions[0].operations.add(createOperationWrapper(operationThree.Id, '14DBE', 0, 0, 0));
        actualSections[0].gwbFunctions[1].operations.add(createOperationWrapper(operationFour.Id, '21DBE', 1, 1, 0));
        actualSections[0].gwbFunctions[2].operations.add(createOperationWrapper(operationFive.Id, '31DBE', 1, 0, 0));
        InitiativeDetailService.saveActualData(initiativeId, JSON.serialize(new SaveRequestWrapperWithSections(actualSections)));
    }

    public static InitiativeSectionWrapper createSection(
        String key,
        String initiativeDateOption,
        Integer year,
        String month,
        Boolean editable,
        List<Plant_Function__c> plantFunctions
    ) {
        InitiativeSectionWrapper section = new InitiativeSectionWrapper();
        section.key = key;
        section.initiativeDateOption = initiativeDateOption;
        section.year = year;
        section.month = month;
        section.editable = editable;
        for (Plant_Function__c pf : plantFunctions) {
            GwbFunctionWrapper row = new GwbFunctionWrapper();
            row.plantFunctionId = pf.Id;
            row.plantFunctionName = pf.Function_Name__c;
            row.crewEditableCount = 3;
            section.gwbFunctions.add(row);
        }
        return section;
    }

    private static Operation_Plan__c createOperationPlan(String name, Integer crews) {
        return new Operation_Plan__c(
            Name = name,
            Shifts_Numeric__c = crews,
            Crews_Numeric__c = crews,
            Days__c = 5
        );
    }

    private static Operation_Plan__c getOrCreateOperationPlan(String name, Integer crews) {
        if (!Test.isRunningTest()) {
            List<Operation_Plan__c> existingPlans = [
                SELECT Id, Name, Crews_Numeric__c
                FROM Operation_Plan__c
                WHERE Shifts_Numeric__c = :crews
                AND Crews_Numeric__c = :crews
                AND Days__c = 5
                LIMIT 1
            ];
            if (!existingPlans.isEmpty()) {
                return existingPlans[0];
            }
        }
        Operation_Plan__c plan = createOperationPlan(name, crews);
        insert plan;
        return plan;
    }

    private static Function__c createFunction(String name) {
        return new Function__c(
            Product_Type__c = 'Vehicle',
            Auth_Sector__c = 'Assembly',
            Classification__c = 'Direct OTS',
            Base_Supp__c = 'Base',
            Included_in_Auth_Plan_of_Record__c = false
        );
    }

    private static Plant_Function__c createPlantFunction(
        Id functionId,
        Id plantId,
        Id plantProgramId,
        Id shiftOverrideId,
        String name,
        String shop,
        String suffix
    ) {
        return new Plant_Function__c(
            Function__c = functionId,
            Plant__c = plantId,
            Plant_Program__c = plantProgramId,
            Shift_OR__c = shiftOverrideId,
            Function_Name__c = name,
            Shop_Manager_View__c = shop,
            Status__c = 'Active',
            External_Id__c = 'PPS-PF-' + suffix
        );
    }

    private static Operation__c createOperation(Id plantId, Id plantFunctionId, String identifier, String shop) {
        return createOperation(plantId, plantFunctionId, identifier, 'DOLLY TRAIN', 'FORK', 'GROUP 1', shop);
    }

    private static Operation__c createOperation(Id plantId, Id plantFunctionId, String identifier, String area, String equipment, String comment, String shop) {
        return new Operation__c(
            Plant__c = plantId,
            Plant_Function__c = plantFunctionId,
            Plant_Shop_Name__c = shop,
            Operation_Identifier__c = identifier,
            Area__c = area,
            Equipment__c = equipment,
            Comment__c = comment,
            Active__c = true,
            External_Id__c = 'PPS-OP-' + identifier + '-' + DateTime.now().getTime()
        );
    }

    private static List<Plant_Function__c> createAdditionalPlantFunctions(DemoData data, Long suffix) {
        List<String> names = new List<String>{
            'C Zone - Rear Compartment',
            'D Zone - Front Floor',
            'E Zone - Convertible Body Structure',
            'F Zone - Body Side Inner LH',
            'F Zone - Body Side Inner RH',
            'H/J Zone - Inner Framing and Respot',
            'K Zone - Body Side Outer LH',
            'K Zone - Body Side Outer RH',
            'L Zone - Outer Framing',
            'N Zone - Battery Tray Assembly'
        };
        List<Function__c> functions = new List<Function__c>();
        for (String functionName : names) {
            functions.add(createFunction(functionName));
        }
        insert functions;

        List<Plant_Function__c> plantFunctions = new List<Plant_Function__c>();
        for (Integer index = 0; index < functions.size(); index++) {
            plantFunctions.add(createPlantFunction(
                functions[index].Id,
                data.plant.Id,
                data.plantProgram.Id,
                Math.mod(index, 3) == 0 ? data.threeCrewPlan.Id : null,
                names[index],
                'GA',
                suffix + '-extra-' + index
            ));
        }
        return plantFunctions;
    }

    private static List<Operation__c> createAdditionalOperations(DemoData data, List<Plant_Function__c> plantFunctions) {
        List<String> identifiers = new List<String>{
            '11DBE', '15DBE', '16DBE', '1DEST', '1EEST',
            '1FEST', '1GEST', '1JEST', '1KEST', '1MEST'
        };
        List<Operation__c> operations = new List<Operation__c>();
        for (Integer index = 0; index < identifiers.size(); index++) {
            Id plantFunctionId = plantFunctions.isEmpty() ? data.plantFunctionOne.Id : plantFunctions[Math.mod(index, plantFunctions.size())].Id;
            operations.add(createOperation(
                data.plant.Id,
                plantFunctionId,
                identifiers[index],
                index < 3 ? 'DOLLY TRAIN' : '(E-FORK) Production Zone',
                index < 3 ? 'TUGGER' : 'FORK',
                index < 3 ? 'GROUP 2' : 'GROUP 1',
                'GA'
            ));
        }
        return operations;
    }

    private static Initiative__c createInitiative(Id plantId, String typeValue, Date effectiveDate, Date endDate, Integer adjustment) {
        return new Initiative__c(
            Plant__c = plantId,
            Shop_Manager_View__c = 'GA',
            Status__c = 'Approved',
            Classification__c = 'OTS',
            Driver__c = 'Productivity',
            Headcount_Type__c = 'Base',
            Initiative_Type__c = typeValue,
            Effective_Date__c = effectiveDate,
            End_Date__c = endDate,
            Position_Adjustment__c = adjustment,
            Description__c = 'PPS backend sample data'
        );
    }

    private static OperationWrapper createOperationWrapper(Id operationId, String identifier, Integer crew1, Integer crew2, Integer crew3) {
        OperationWrapper wrapper = new OperationWrapper();
        wrapper.operationId = operationId;
        wrapper.operationIdentifier = identifier;
        wrapper.crew1 = crew1;
        wrapper.crew2 = crew2;
        wrapper.crew3 = crew3;
        return wrapper;
    }

    public class SaveRequestWrapperWithSections {
        public List<InitiativeSectionWrapper> sections;

        public SaveRequestWrapperWithSections(List<InitiativeSectionWrapper> sections) {
            this.sections = sections;
        }
    }
}