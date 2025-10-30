/**
 * Interface for queueable classes that can be chained with finalizer support
 * All queueable classes participating in the chain must implement this interface
 */
public interface IQueueableChainable {
    /**
     * Get the configuration for the current queueable
     * @return Queueable_Chain_Config__mdt configuration record
     */
    Queueable_Chain_Config__mdt getQueueableConfig();
    
    /**
     * Handle any pre-execution logic
     */
    void onBeforeExecution();
    
    /**
     * Handle any post-execution logic
     * @param jobId AsyncApexJob ID of the queueable execution
     */
    void onAfterExecution(Id jobId);
    
    /**
     * Get current queueable class name
     * @return String class name
     */
    String getCurrentQueueableName();
    
    /**
     * Handle errors that occur during execution
     * @param e Exception that occurred
     */
    void onExecutionError(Exception e);
    
    /**
     * Handle finalizer completion
     * @param result System.FinalizerContext result
     */
    void onFinalizerComplete(System.FinalizerContext result);
    
    /**
     * Set runtime parameters for the queueable
     * @param runtimeParameters Map of parameters passed at execution time
     */
    void setRuntimeParameters(Map<String, Object> runtimeParameters);
    
    /**
     * Get combined parameters (runtime + configuration)
     * @return Map<String, Object> merged parameters
     */
    Map<String, Object> getEffectiveParameters();
}