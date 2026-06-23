@IsTest
private class ClassificationDecoderTest {
    @IsTest
    static void toClassificationGroupNormalizesConfiguredValuesAndGroups() {
        System.assertEquals(null, ClassificationDecoder.toClassificationGroup(null), 'Null values should remain null.');
        System.assertEquals('', ClassificationDecoder.toClassificationGroup(''), 'Blank values should remain blank.');
        System.assertEquals('OTS', ClassificationDecoder.toClassificationGroup('Direct OTS'));
        System.assertEquals('OTS', ClassificationDecoder.toClassificationGroup(' Indirect OTS '), 'Whitespace should be ignored.');
        System.assertEquals('Skilled', ClassificationDecoder.toClassificationGroup('Indirect Skilled'));
        System.assertEquals('Salaried', ClassificationDecoder.toClassificationGroup('Salaried'));
        System.assertEquals('OTS', ClassificationDecoder.toClassificationGroup('OTS'), 'Group values should decode to themselves.');
        System.assertEquals(null, ClassificationDecoder.toClassificationGroup('Unknown Classification'));
    }

    @IsTest
    static void getClassificationsForGroupReturnsConfiguredValues() {
        Set<String> otsClassifications = ClassificationDecoder.getClassificationsForGroup('OTS');
        Set<String> skilledClassifications = ClassificationDecoder.getClassificationsForGroup('Indirect Skilled');
        Set<String> unknownClassifications = ClassificationDecoder.getClassificationsForGroup('Unknown Classification');

        System.assert(otsClassifications.contains('OTS'), 'The group value should be included.');
        System.assert(otsClassifications.contains('Direct OTS'), 'Configured Direct OTS should be included.');
        System.assert(otsClassifications.contains('Indirect OTS'), 'Configured Indirect OTS should be included.');
        System.assert(skilledClassifications.contains('Skilled'), 'Passing a classification value should resolve to its group.');
        System.assert(skilledClassifications.contains('Indirect Skilled'), 'Configured Skilled value should be included.');
        System.assertEquals(0, unknownClassifications.size(), 'Unknown groups should return an empty set.');
        System.assertEquals(0, ClassificationDecoder.getClassificationsForGroup(null).size(), 'Blank groups should return an empty set.');
    }
}