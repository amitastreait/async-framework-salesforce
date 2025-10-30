/**
 * Standard Finalizer for queueable chain continuation
 * Uses standard System.FinalizerContext as per Salesforce documentation
 */
public class QueueableChainFinalizer implements System.Finalizer {
    
    private String currentQueueableName;
    
    public QueueableChainFinalizer(String queueableName) {
        this.currentQueueableName = queueableName;
    }
    
    /**
     * Execute finalizer logic using standard System.FinalizerContext
     * @param finalizerContext System.FinalizerContext
     */
    public void execute(System.FinalizerContext finalizerContext) {
        try {
            logInfo('Finalizer executing for: ' + currentQueueableName + 
                   ', Parent Job ID: ' + finalizerContext.getAsyncApexJobId() +
                   ', Request ID: ' + finalizerContext.getRequestId());
            
            // Get the queueable configuration to determine next steps
            Queueable_Chain_Config__mdt config = QueueableChainExecutor.getInstance()
                .getQueueableConfig(currentQueueableName);
            
            if (config == null) {
                logInfo('No configuration found for: ' + currentQueueableName);
                return;
            }
            
            // Notify the queueable instance if it implements IQueueableChainable
            notifyQueueableInstance(finalizerContext);
            
            // Continue the chain if configured to do so
            if (shouldContinueChain(config, finalizerContext)) {
                QueueableChainExecutor.getInstance().continueChain(
                    currentQueueableName,
                    finalizerContext.getAsyncApexJobId(),
                    true // fromFinalizer = true
                );
            }
            
            logInfo('Finalizer completed for: ' + currentQueueableName);
            
        } catch (Exception e) {
            logError('Error in finalizer for: ' + currentQueueableName, e);
        }
    }
    
    /**
     * Notify the queueable instance about finalizer completion
     */
    private void notifyQueueableInstance(System.FinalizerContext finalizerContext) {
        try {
            // Create a new instance to call the finalizer callback
            // Note: The original instance is not available in finalizer context
            Type queueableType = Type.forName(currentQueueableName);
            if (queueableType != null) {
                Object queueableObject = queueableType.newInstance();
                if (queueableObject instanceof IQueueableChainable) {
                    ((IQueueableChainable) queueableObject).onFinalizerComplete(finalizerContext);
                }
            }
        } catch (Exception e) {
            logError('Error notifying queueable instance: ' + currentQueueableName, e);
        }
    }
    
    /**
     * Determine if chain should continue based on configuration and job result
     */
    private Boolean shouldContinueChain(Queueable_Chain_Config__mdt config, System.FinalizerContext finalizerContext) {
        // If no next queueable configured, don't continue
        if (String.isBlank(config.Next_Queueable__c)) {
            return false;
        }
        
        // If configured to continue on failure, always continue
        if (config.Continue_On_Failure__c) {
            return true;
        }
        
        // Check job status if available
        try {
            Id jobId = finalizerContext.getAsyncApexJobId();
            if (jobId != null) {
                AsyncApexJob job = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId LIMIT 1];
                // Only continue if job completed successfully
                return job.Status == 'Completed';
            }
        } catch (Exception e) {
            logError('Error checking job status', e);
        }
        
        // Default to continue if we can't determine status
        return true;
    }
    
    /**
     * Log info message
     */
    private void logInfo(String message) {
        System.debug(LoggingLevel.INFO, '[QueueableChainFinalizer] ' + message);
    }
    
    /**
     * Log error message
     */
    private void logError(String message, Exception e) {
        String errorMsg = '[QueueableChainFinalizer] ' + message;
        if (e != null) {
            errorMsg += ' - Error: ' + e.getMessage();
        }
        System.debug(LoggingLevel.ERROR, errorMsg);
    }
}