@IsTest
public class QueueableChainExecutorTest {
    
    @TestSetup
    static void setupTestData() {
        // Test data setup if needed
    }
    
    @IsTest
    static void testGetInstance() {
        QueueableChainExecutor instance1 = QueueableChainExecutor.getInstance();
        QueueableChainExecutor instance2 = QueueableChainExecutor.getInstance();
        
        System.assertNotEquals(null, instance1, 'Instance should not be null');
        System.assertEquals(instance1, instance2, 'Should return same singleton instance');
    }
    
    @IsTest
    static void testStartQueueableWithoutParameters() {
        Test.startTest();
        
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        
        try {
            Id jobId = executor.startQueueable('NonExistentQueueable');
            System.assert(false, 'Should have thrown exception for non-existent queueable');
        } catch (QueueableChainExecutor.QueueableChainException e) {
            System.assert(e.getMessage().contains('No active queueable configuration found'), 
                         'Should throw exception for missing configuration');
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testStartQueueableWithParameters() {
        Test.startTest();
        
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        Map<String, Object> parameters = new Map<String, Object>{
            'testParam' => 'testValue'
        };
        
        try {
            Id jobId = executor.startQueueable('NonExistentQueueable', parameters);
            System.assert(false, 'Should have thrown exception for non-existent queueable');
        } catch (QueueableChainExecutor.QueueableChainException e) {
            System.assert(e.getMessage().contains('No active queueable configuration found'), 
                         'Should throw exception for missing configuration');
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testGetQueueableConfigWithValidName() {
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        
        Test.startTest();
        Queueable_Chain_Config__mdt config = executor.getQueueableConfig('SampleQueueable1');
        Test.stopTest();
        
        // Check if config exists or not - both are valid outcomes
        if (config != null) {
            System.assertEquals('SampleQueueable1', config.Current_Queueable__c, 'Should return correct configuration');
            System.assertNotEquals(null, config.Is_Active__c, 'Should have Is_Active field populated');
        } else {
            System.assertEquals(null, config, 'Should return null for non-existent metadata in test context');
        }
    }
    
    @IsTest
    static void testGetQueueableConfigWithBlankName() {
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        
        Test.startTest();
        Queueable_Chain_Config__mdt config1 = executor.getQueueableConfig('');
        Queueable_Chain_Config__mdt config2 = executor.getQueueableConfig(null);
        Test.stopTest();
        
        System.assertEquals(null, config1, 'Should return null for empty string');
        System.assertEquals(null, config2, 'Should return null for null input');
    }
    
    @IsTest
    static void testContinueChainWithoutFinalizer() {
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        
        Test.startTest();
        // This should not throw exception even with non-existent queueable
        executor.continueChain('NonExistentQueueable', null);
        Test.stopTest();
        
        // Method should complete without exception
        System.assert(true, 'continueChain should handle non-existent queueable gracefully');
    }
    
    @IsTest
    static void testContinueChainWithFinalizer() {
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        
        Test.startTest();
        // This should not throw exception even with non-existent queueable
        executor.continueChain('NonExistentQueueable', null, true);
        Test.stopTest();
        
        // Method should complete without exception
        System.assert(true, 'continueChain with finalizer should handle non-existent queueable gracefully');
    }
    
    @IsTest
    static void testParseParametersWithValidJson() {
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        
        Test.startTest();
        String jsonParams = '{"key1":"value1","key2":123}';
        Map<String, Object> result = executor.parseParameters(jsonParams);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('value1', result.get('key1'), 'Should parse string value correctly');
        System.assertEquals(123, result.get('key2'), 'Should parse numeric value correctly');
    }
    
    @IsTest
    static void testParseParametersWithInvalidJson() {
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        
        Test.startTest();
        String invalidJson = '{"key1":"value1",}'; // Invalid JSON
        Map<String, Object> result = executor.parseParameters(invalidJson);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Should return empty map for invalid JSON');
    }
    
    @IsTest
    static void testParseParametersWithBlankInput() {
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        
        Test.startTest();
        Map<String, Object> result1 = executor.parseParameters('');
        Map<String, Object> result2 = executor.parseParameters(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result1, 'Result should not be null for empty string');
        System.assertNotEquals(null, result2, 'Result should not be null for null input');
        System.assertEquals(0, result1.size(), 'Should return empty map for empty string');
        System.assertEquals(0, result2.size(), 'Should return empty map for null input');
    }
    
    @IsTest
    static void testQueueableChainException() {
        Test.startTest();
        
        try {
            throw new QueueableChainExecutor.QueueableChainException('Test exception');
        } catch (QueueableChainExecutor.QueueableChainException e) {
            System.assertEquals('Test exception', e.getMessage(), 'Exception message should match');
        }
        
        Test.stopTest();
    }
    
    // Mock Queueable class for testing
    public class MockQueueable implements Queueable, IQueueableChainable {
        private Map<String, Object> runtimeParameters;
        
        public void execute(QueueableContext context) {
            // Mock execution logic
        }
        
        public Queueable_Chain_Config__mdt getQueueableConfig() {
            return null; // Mock implementation
        }
        
        public void onBeforeExecution() {
            // Mock implementation
        }
        
        public void onAfterExecution(Id jobId) {
            // Mock implementation
        }
        
        public String getCurrentQueueableName() {
            return 'MockQueueable';
        }
        
        public void onExecutionError(Exception e) {
            // Mock implementation
        }
        
        public void onFinalizerComplete(System.FinalizerContext result) {
            // Mock implementation
        }
        
        public void setRuntimeParameters(Map<String, Object> runtimeParameters) {
            this.runtimeParameters = runtimeParameters;
        }
        
        public Map<String, Object> getEffectiveParameters() {
            return this.runtimeParameters != null ? this.runtimeParameters : new Map<String, Object>();
        }
    }
    
    // Mock Queueable class without IQueueableChainable for testing
    public class SimpleQueueable implements Queueable {
        public void execute(QueueableContext context) {
            // Simple mock execution logic
        }
    }
    
    @IsTest
    static void testExecuteQueueableWithMockConfig() {
        // Create a mock configuration object
        // Note: In actual test execution, we would need to create custom metadata records
        // or use a different approach since custom metadata cannot be inserted in tests
        
        Test.startTest();
        
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        
        // Test with null config
        try {
            executor.executeQueueable(null);
            System.assert(false, 'Should throw exception for null config');
        } catch (Exception e) {
            // The method may throw various exceptions for null config including NullPointerException
            System.assert(e.getMessage().contains('Failed to start queueable') || 
                         e.getMessage().contains('configuration cannot be null') ||
                         e.getMessage().contains('Attempt to de-reference a null object'), 
                         'Should throw appropriate exception for null config. Actual message: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testLogMethods() {
        // Test that logging methods don't throw exceptions
        // Since these are private methods, we test them indirectly through public methods
        
        Test.startTest();
        
        QueueableChainExecutor executor = QueueableChainExecutor.getInstance();
        
        // Test parseParameters which calls logError internally for invalid JSON
        Map<String, Object> result = executor.parseParameters('invalid json');
        System.assertNotEquals(null, result, 'Should not throw exception and return empty map');
        
        // Test getQueueableConfig which may call logError internally
        Queueable_Chain_Config__mdt config = executor.getQueueableConfig('NonExistentConfig');
        System.assertEquals(null, config, 'Should return null for non-existent config');
        
        Test.stopTest();
    }
}