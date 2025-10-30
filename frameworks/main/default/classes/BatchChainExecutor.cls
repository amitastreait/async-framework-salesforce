/**
 * Main executor class for handling batch job chaining
 * Uses Current_Batch__c as primary lookup mechanism
 */
public class BatchChainExecutor {
    private static final String CLASS_NAME = 'BatchChainExecutor';
    private static final Integer DEFAULT_BATCH_SIZE = 200;
    private static final Integer DEFAULT_DELAY = 0;
    
    // Singleton instance
    private static BatchChainExecutor instance;
    
    // Private constructor
    private BatchChainExecutor() {}
    
    /**
     * Get singleton instance
     */
    public static BatchChainExecutor getInstance() {
        if (instance == null) {
            instance = new BatchChainExecutor();
        }
        return instance;
    }
    
    /**
     * Start batch execution by current batch name
     * @param currentBatchName The batch class name to start with
     */
    public Id startBatch(String currentBatchName) {
        return startBatch(currentBatchName, null);
    }
    
    /**
     * Start batch execution by current batch name with parameters
     * @param currentBatchName The batch class name to start with
     * @param parameters Map of parameters to pass to the batch
     */
    public Id startBatch(String currentBatchName, Map<String, Object> parameters) {
        try {
            Batch_Chain_Configuration__mdt config = getBatchConfig(currentBatchName);
            
            if (config == null) {
                throw new BatchChainException('No active batch configuration found for: ' + currentBatchName);
            }
            
            return executeBatch(config, parameters);
            
        } catch (Exception e) {
            logError('Error starting batch: ' + currentBatchName, e);
            throw new BatchChainException('Failed to start batch: ' + e.getMessage());
        }
    }
    
    /**
     * Execute individual batch job
     * @param config Batch configuration metadata
     * @return Id Job ID of the executed batch
     */
    public Id executeBatch(Batch_Chain_Configuration__mdt config) {
        return executeBatch(config, null);
    }
    
    /**
     * Execute individual batch job with parameters
     * @param config Batch configuration metadata
     * @param parameters Map of parameters to pass to the batch
     * @return Id Job ID of the executed batch
     */
    public Id executeBatch(Batch_Chain_Configuration__mdt config, Map<String, Object> parameters) {
        try {
            // Validate configuration
            validateConfig(config);
            
            // Get batch instance
            Object batchInstance = getBatchInstance(config.Current_Batch__c);
            
            // Initialize batch with parameters if implements IBatchChainable
            if (batchInstance instanceof IBatchChainable) {
                IBatchChainable chainableBatch = (IBatchChainable) batchInstance;
                if (parameters != null) {
                    chainableBatch.initializeWithParameters(parameters);
                }
                chainableBatch.onBeforeExecution(parameters);
            }
            
            // Determine batch size
            Integer batchSize = config.Batch_Size__c != null ? Integer.valueOf(config.Batch_Size__c) : DEFAULT_BATCH_SIZE;
            
            // Submit batch job - handle generic batchable
            Id jobId;
            Integer delayInMinutes = config.Execution_Delay__c != null ? Integer.valueOf(config.Execution_Delay__c) : DEFAULT_BATCH_SIZE;
            if ( delayInMinutes <= 0) {
                jobId = queueBatchJob(batchInstance, parameters, config);
            } else {
                jobId = queueDelayedBatchJob(batchInstance, parameters, delayInMinutes, config);
            }
            // Log execution
            logBatchExecution(config, jobId);
            return jobId;
        } catch (Exception e) {
            logError('Error executing batch: ' + config.Current_Batch__c, e);
            handleBatchFailure(config, e);
            throw e;
        }
    }

    public Id queueBatchJob(Object batchInstance, Map<String, Object> parameters, Batch_Chain_Configuration__mdt config){
        Id jobId; 
        Integer batchSize = config.Batch_Size__c != null ? Integer.valueOf(config.Batch_Size__c) : DEFAULT_BATCH_SIZE;
        if (batchInstance instanceof Database.Batchable<SObject>) {
            jobId = Database.executeBatch((Database.Batchable<SObject>) batchInstance, batchSize);
        } else {
            // For non-SObject batches, we need to cast appropriately
            // This requires the batch class to be properly typed
            jobId = Database.executeBatch((Database.Batchable<Object>) batchInstance, batchSize);
        }
        return jobId;
    }

    public Id queueDelayedBatchJob(Object batchInstance, Map<String, Object> parameters, Integer delayInMinutes, Batch_Chain_Configuration__mdt config){
        Id jobId; 
        String jobName = 'BatchChain_' + config.Current_Batch__c + '_' + System.now().getTime();
        Integer batchSize = config.Batch_Size__c != null ? Integer.valueOf(config.Batch_Size__c) : DEFAULT_BATCH_SIZE;
        if (batchInstance instanceof Database.Batchable<SObject>) {
            jobId = System.scheduleBatch((Database.Batchable<SObject>)batchInstance, jobName, delayInMinutes ?? DEFAULT_DELAY, batchSize);
        } else {
            jobId = System.scheduleBatch((Database.Batchable<Object>)batchInstance, jobName, delayInMinutes ?? DEFAULT_DELAY, batchSize);
        }
        return jobId;
    }
    
    /**
     * Continue to next batch in chain
     * Called from finish() method of current batch
     * @param currentBatchName Current batch class name
     * @param jobResult AsyncApexJob result of current batch
     */
    public void continueChain(String currentBatchName, AsyncApexJob jobResult) {
        continueChain(currentBatchName, jobResult, null);
    }
    
    /**
     * Continue to next batch in chain with parameters
     * Called from finish() method of current batch
     * @param currentBatchName Current batch class name
     * @param jobResult AsyncApexJob result of current batch
     * @param parameters Map of parameters to pass to the next batch
     */
    public void continueChain(String currentBatchName, AsyncApexJob jobResult, Map<String, Object> parameters) {
        try {
            // Get current batch configuration
            Batch_Chain_Configuration__mdt currentConfig = getBatchConfig(currentBatchName);
            
            if (currentConfig == null || String.isBlank(currentConfig.Next_Batch__c)) {
                logInfo('End of batch chain reached for: ' + currentBatchName);
                return;
            }
            
            // Check if current batch completed successfully
            if (jobResult.Status != 'Completed' || jobResult.NumberOfErrors > 0) {
                logError('Previous batch failed, stopping chain: ' + currentBatchName, null);
                handleChainFailure(currentConfig, jobResult);
                return;
            }
            
            // Get next batch configuration
            Batch_Chain_Configuration__mdt nextConfig = getBatchConfig(currentConfig.Next_Batch__c);
            
            if (nextConfig == null) {
                logError('Next batch configuration not found: ' + currentConfig.Next_Batch__c, null);
                return;
            }
            
            // Schedule next batch with delay if specified
            scheduleNextBatch(nextConfig, currentConfig.Execution_Delay__c, parameters);
            
        } catch (Exception e) {
            logError('Error continuing batch chain from: ' + currentBatchName, e);
        }
    }
    
    /**
     * Get batch configuration by current batch name
     * @param currentBatchName The batch class name
     * @return Batch_Chain_Configuration__mdt configuration record
     */
    public Batch_Chain_Configuration__mdt getBatchConfig(String currentBatchName) {
        if (String.isBlank(currentBatchName)) {
            return null;
        }
        
        List<Batch_Chain_Configuration__mdt> configs = [
            SELECT Id, Current_Batch__c, Next_Batch__c, Execution_Delay__c, 
                   Is_Active__c, Batch_Size__c, Description__c, 
                   Max_Retries__c
            FROM Batch_Chain_Configuration__mdt 
            WHERE Current_Batch__c = :currentBatchName 
            AND Is_Active__c = true
            LIMIT 1
        ];
        
        return configs.isEmpty() ? null : configs[0];
    }
    
    /**
     * Schedule next batch execution
     * @param nextConfig Next batch configuration
     * @param delaySeconds Delay in seconds (can be null)
     */
    private void scheduleNextBatch(Batch_Chain_Configuration__mdt nextConfig, Decimal delaySeconds) {
        scheduleNextBatch(nextConfig, delaySeconds, null);
    }
    
    /**
     * Schedule next batch execution with parameters
     * @param nextConfig Next batch configuration
     * @param delaySeconds Delay in seconds (can be null)
     * @param parameters Map of parameters to pass to the next batch
     */
    private void scheduleNextBatch(Batch_Chain_Configuration__mdt nextConfig, Decimal delaySeconds, Map<String, Object> parameters) {
        executeBatch(nextConfig, parameters);
    }
    
    /**
     * Get batch instance by class name
     * @param className The batch class name
     * @return Object instance that implements Database.Batchable
     */
    private Object getBatchInstance(String className) {
        Type batchType = Type.forName(className);
        
        if (batchType == null) {
            throw new BatchChainException('Batch class not found: ' + className);
        }
        
        Object batchObject = batchType.newInstance();
        
        // Check if it's a valid batchable (either SObject or generic type)
        if (!(batchObject instanceof Database.Batchable<SObject>) && 
            !(batchObject instanceof Database.Batchable<Object>)) {
            throw new BatchChainException('Class is not a valid Batchable: ' + className);
        }
        
        return batchObject;
    }
    
    /**
     * Validate batch configuration
     * @param config Batch configuration to validate
     */
    private void validateConfig(Batch_Chain_Configuration__mdt config) {
        if (config == null) {
            throw new BatchChainException('Batch configuration cannot be null');
        }
        
        if (String.isBlank(config.Current_Batch__c)) {
            throw new BatchChainException('Current batch class name cannot be empty');
        }
        
        if (!config.Is_Active__c) {
            throw new BatchChainException('Batch configuration is not active: ' + config.Current_Batch__c);
        }
    }
    
    /**
     * Handle batch execution failure
     * @param config Batch configuration
     * @param e Exception that occurred
     */
    private void handleBatchFailure(Batch_Chain_Configuration__mdt config, Exception e) {
        logError('Batch execution failed: ' + config.Current_Batch__c, e);
        
    }
    
    /**
     * Handle chain failure
     * @param config Current batch configuration
     * @param jobResult AsyncApexJob result
     */
    private void handleChainFailure(Batch_Chain_Configuration__mdt config, AsyncApexJob jobResult) {
        String errorMsg = 'Batch chain stopped due to failure in: ' + config.Current_Batch__c + ', Status: ' + jobResult.Status +  ', Errors: ' + jobResult.NumberOfErrors;
        logError(errorMsg, null);
    }
    
    /**
     * Log batch execution
     * @param config Batch configuration
     * @param jobId Job ID
     */
    private void logBatchExecution(Batch_Chain_Configuration__mdt config, Id jobId) {
        String message = 'Batch executed: ' + config.Current_Batch__c + ', Job ID: ' + jobId + ', Next Batch: ' + (config.Next_Batch__c != null ? config.Next_Batch__c : 'None');
        logInfo(message);
    }
    
    /**
     * Log info message
     * @param message Info message
     */
    private void logInfo(String message) {
        System.debug(LoggingLevel.INFO, '[BatchChainExecutor] ' + message);
    }
    
    /**
     * Log error message
     * @param message Error message
     * @param e Exception (can be null)
     */
    private void logError(String message, Exception e) {
        String errorMsg = '[BatchChainExecutor] ' + message;
        if (e != null) {
            errorMsg += ' - Error: ' + e.getMessage() + ', Stack Trace: ' + e.getStackTraceString();
        }
        System.debug(LoggingLevel.ERROR, errorMsg);
    }
    
    /**
     * Custom exception class
     */
    public class BatchChainException extends Exception {}
}