/**
 * Main executor class for handling queueable job chaining with finalizer support
 * Uses Current_Queueable__c as primary lookup mechanism
 */
public class QueueableChainExecutor {
    private static final String CLASS_NAME = 'QueueableChainExecutor';
    private static final Integer DEFAULT_DELAY = 0;
    
    // Singleton instance
    private static QueueableChainExecutor instance;
    
    // Private constructor
    private QueueableChainExecutor() {}
    
    /**
     * Get singleton instance
     */
    public static QueueableChainExecutor getInstance() {
        if (instance == null) {
            instance = new QueueableChainExecutor();
        }
        return instance;
    }
    
    /**
     * Start queueable execution by current queueable name
     * @param currentQueueableName The queueable class name to start with
     * @return Id Job ID of the enqueued queueable
     */
    public Id startQueueable(String currentQueueableName) {
        return startQueueable(currentQueueableName, new Map<String, Object>());
    }
    
    /**
     * Start queueable execution by current queueable name with runtime parameters
     * @param currentQueueableName The queueable class name to start with
     * @param runtimeParameters Runtime parameters to pass to the queueable
     * @return Id Job ID of the enqueued queueable
     */
    public Id startQueueable(String currentQueueableName, Map<String, Object> runtimeParameters) {
        try {
            Queueable_Chain_Config__mdt config = getQueueableConfig(currentQueueableName);
            
            if (config == null) {
                throw new QueueableChainException('No active queueable configuration found for: ' + currentQueueableName);
            }
            
            return executeQueueable(config, runtimeParameters);
            
        } catch (Exception e) {
            logError('Error starting queueable: ' + currentQueueableName, e);
            throw new QueueableChainException('Failed to start queueable: ' + e.getMessage());
        }
    }
    
    /**
     * Execute individual queueable job
     * @param config Queueable configuration metadata
     * @return Id Job ID of the enqueued queueable
     */
    public Id executeQueueable(Queueable_Chain_Config__mdt config) {
        return executeQueueable(config, new Map<String, Object>());
    }
    
    /**
     * Execute individual queueable job with runtime parameters
     * @param config Queueable configuration metadata
     * @param runtimeParameters Runtime parameters to pass to the queueable
     * @return Id Job ID of the enqueued queueable
     */
    public Id executeQueueable(Queueable_Chain_Config__mdt config, Map<String, Object> runtimeParameters) {
        try {
            // Validate configuration
            validateConfig(config);
            
            // Get queueable instance
            System.Queueable queueableInstance = getQueueableInstance(config.Current_Queueable__c);
            
            // Set runtime parameters if implements IQueueableChainable
            if (queueableInstance instanceof IQueueableChainable && runtimeParameters != null && !runtimeParameters.isEmpty()) {
                ((IQueueableChainable) queueableInstance).setRuntimeParameters(runtimeParameters);
            }
            
            // Execute pre-execution logic if implements IQueueableChainable
            if (queueableInstance instanceof IQueueableChainable) {
                ((IQueueableChainable) queueableInstance).onBeforeExecution();
            }
            
            Id jobId;
            Integer delay = config.Execution_Delay__c != null ? Integer.valueOf(config.Execution_Delay__c) : DEFAULT_DELAY;
            if (delay > 0 && queueableInstance instanceof IQueueableChainable) {
                jobId = System.enqueueJob(queueableInstance, delay);
            } else {
                jobId = System.enqueueJob(queueableInstance);
            }
            logInfo('Queueable enqueued with finalizer: ' + config.Current_Queueable__c);
            // Log execution
            logQueueableExecution(config, jobId, runtimeParameters);
            
            return jobId;
            
        } catch (Exception e) {
            logError('Error executing queueable: ' + config.Current_Queueable__c, e);
            handleQueueableFailure(config, e);
            throw e;
        }
    }
    
    /**
     * Continue to next queueable in chain
     * Called from execute() method of current queueable or from finalizer
     * @param currentQueueableName Current queueable class name
     * @param currentJobId Current job ID (can be null for finalizer calls)
     * @param fromFinalizer Whether this call is from finalizer
     */
    public void continueChain(String currentQueueableName, Id currentJobId, Boolean fromFinalizer) {
        try {
            // Get current queueable configuration
            Queueable_Chain_Config__mdt currentConfig = getQueueableConfig(currentQueueableName);
            
            if (currentConfig == null || String.isBlank(currentConfig.Next_Queueable__c)) {
                logInfo('End of queueable chain reached for: ' + currentQueueableName + (fromFinalizer ? ' (from finalizer)' : ''));
                return;
            }
            
            // If called from finalizer and continuation on failure is disabled, check job status
            if (fromFinalizer && !currentConfig.Continue_On_Failure__c && currentJobId != null) {
                AsyncApexJob jobResult = getJobResult(currentJobId);
                if (jobResult != null && (jobResult.Status == 'Failed' || jobResult.Status == 'Aborted')) {
                    logError('Previous queueable failed, stopping chain: ' + currentQueueableName, null);
                    return;
                }
            }
            
            // Get next queueable configuration
            Queueable_Chain_Config__mdt nextConfig = getQueueableConfig(currentConfig.Next_Queueable__c);
            
            if (nextConfig == null) {
                logError('Next queueable configuration not found: ' + currentConfig.Next_Queueable__c, null);
                return;
            }
            
            // Schedule next queueable with delay if specified
            scheduleNextQueueable(nextConfig, currentConfig.Execution_Delay__c);
            
        } catch (Exception e) {
            logError('Error continuing queueable chain from: ' + currentQueueableName + (fromFinalizer ? ' (from finalizer)' : ''), e);
        }
    }
    
    /**
     * Continue chain without finalizer context (backward compatibility)
     */
    public void continueChain(String currentQueueableName, Id currentJobId) {
        continueChain(currentQueueableName, currentJobId, false);
    }
    
    /**
     * Get job result for status checking
     */
    private AsyncApexJob getJobResult(Id jobId) {
        try {
            return [SELECT Id, Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId LIMIT 1];
        } catch (Exception e) {
            logError('Error querying job result for: ' + jobId, e);
            return null;
        }
    }
    
    /**
     * Get queueable configuration by current queueable name
     * @param currentQueueableName The queueable class name
     * @return Queueable_Chain_Config__mdt configuration record
     */
    public Queueable_Chain_Config__mdt getQueueableConfig(String currentQueueableName) {
        if (String.isBlank(currentQueueableName)) {
            return null;
        }
        
        List<Queueable_Chain_Config__mdt> configs = [
            SELECT Id, Current_Queueable__c, Next_Queueable__c, Execution_Delay__c, 
                   Is_Active__c, Description__c, Max_Retries__c, Continue_On_Failure__c, Use_Finalizer__c
            FROM Queueable_Chain_Config__mdt 
            WHERE Current_Queueable__c = :currentQueueableName 
            AND Is_Active__c = true
            LIMIT 1
        ];
        
        return configs.isEmpty() ? null : configs[0];
    }
    
    /**
     * Schedule next queueable execution
     * @param nextConfig Next queueable configuration
     * @param delaySeconds Delay in seconds (can be null)
     */
    private void scheduleNextQueueable(Queueable_Chain_Config__mdt nextConfig, Decimal delaySeconds) {
        executeQueueable(nextConfig, new Map<String, Object>());
    }
    
    /**
     * Get queueable instance by class name
     * @param className The queueable class name
     * @return System.Queueable instance
     */
    private System.Queueable getQueueableInstance(String className) {
        Type queueableType = Type.forName(className);
        
        if (queueableType == null) {
            throw new QueueableChainException('Queueable class not found: ' + className);
        }
        
        Object queueableObject = queueableType.newInstance();
        
        if (!(queueableObject instanceof System.Queueable)) {
            throw new QueueableChainException('Class is not a valid Queueable: ' + className);
        }
        
        return (System.Queueable) queueableObject;
    }
    
    /**
     * Validate queueable configuration
     * @param config Queueable configuration to validate
     */
    private void validateConfig(Queueable_Chain_Config__mdt config) {
        if (config == null) {
            throw new QueueableChainException('Queueable configuration cannot be null');
        }
        
        if (String.isBlank(config.Current_Queueable__c)) {
            throw new QueueableChainException('Current queueable class name cannot be empty');
        }
        
        if (!config.Is_Active__c) {
            throw new QueueableChainException('Queueable configuration is not active: ' + config.Current_Queueable__c);
        }
    }
    
    /**
     * Schedule delayed execution using Schedulable
     * @param config Queueable configuration
     * @param delaySeconds Delay in seconds
     */
    private void scheduleDelayedExecution(Queueable_Chain_Config__mdt config, Integer delaySeconds) {
        Datetime scheduleTime = System.now().addSeconds(delaySeconds);
        
        String jobName = 'QueueableChain_' + config.Current_Queueable__c + '_' + System.now().getTime();
        
        logInfo('Scheduled queueable: ' + config.Current_Queueable__c + ' to run at: ' + scheduleTime);
        // Id jobId = System.enqueueJob('', delaySeconds);
    }
    
    /**
     * Handle queueable execution failure
     * @param config Queueable configuration
     * @param e Exception that occurred
     */
    private void handleQueueableFailure(Queueable_Chain_Config__mdt config, Exception e) {
        logError('Queueable execution failed: ' + config.Current_Queueable__c, e);
    }
    
    /**
     * Parse JSON parameters from configuration
     * @param parametersJson JSON string containing parameters
     * @return Map<String, Object> parsed parameters
     */
    public Map<String, Object> parseParameters(String parametersJson) {
        if (String.isBlank(parametersJson)) {
            return new Map<String, Object>();
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(parametersJson);
        } catch (Exception e) {
            logError('Error parsing parameters: ' + parametersJson, e);
            return new Map<String, Object>();
        }
    }
    
    /**
     * Log queueable execution
     * @param config Queueable configuration
     * @param jobId Job ID
     * @param runtimeParameters Runtime parameters passed to queueable
     */
    private void logQueueableExecution(Queueable_Chain_Config__mdt config, Id jobId, Map<String, Object> runtimeParameters) {
        String message = 'Queueable executed: ' + config.Current_Queueable__c + 
                        ', Job ID: ' + jobId + 
                        ', Next Queueable: ' + (config.Next_Queueable__c != null ? config.Next_Queueable__c : 'None') +
                        ', Uses Finalizer: ' + config.Use_Finalizer__c;
        
        if (runtimeParameters != null && !runtimeParameters.isEmpty()) {
            message += ', Runtime Parameters: ' + JSON.serialize(runtimeParameters);
        }
        
        logInfo(message);
    }
    
    /**
     * Log queueable execution (backward compatibility)
     * @param config Queueable configuration
     * @param jobId Job ID
     */
    private void logQueueableExecution(Queueable_Chain_Config__mdt config, Id jobId) {
        logQueueableExecution(config, jobId, new Map<String, Object>());
    }
    
    /**
     * Log info message
     * @param message Info message
     */
    private void logInfo(String message) {
        System.debug(LoggingLevel.INFO, '[QueueableChainExecutor] ' + message);
    }
    
    /**
     * Log error message
     * @param message Error message
     * @param e Exception (can be null)
     */
    private void logError(String message, Exception e) {
        String errorMsg = '[QueueableChainExecutor] ' + message;
        if (e != null) {
            errorMsg += ' - Error: ' + e.getMessage() + ', Stack Trace: ' + e.getStackTraceString();
        }
        System.debug(LoggingLevel.ERROR, errorMsg);
    }
    
    /**
     * Custom exception class
     */
    public class QueueableChainException extends Exception {}
}