/**
 * Interface for batch classes that can be chained
 * All batchable classes participating in the chain must implement this interface
 * Generic interface to support different batch parameter types
 */
public interface IBatchChainable {
    /**
     * Get the configuration for the current batch
     * @return Batch_Chain_Configuration__mdt configuration record
     */
    Batch_Chain_Configuration__mdt getBatchConfig();
    
    /**
     * Handle any pre-execution logic with optional parameters
     * @param parameters Map of parameters to pass to the batch
     */
    void onBeforeExecution(Map<String, Object> parameters);
    
    /**
     * Handle any post-execution logic
     * @param result AsyncApexJob result of the batch execution
     */
    void onAfterExecution(AsyncApexJob result);
    
    /**
     * Get current batch class name
     * @return String class name
     */
    String getCurrentBatchName();
    
    /**
     * Initialize batch with parameters
     * @param parameters Map of parameters for batch initialization
     */
    void initializeWithParameters(Map<String, Object> parameters);
}