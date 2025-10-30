/**
 * Scheduler class for delayed batch execution
 */
public class BatchChainScheduler implements Schedulable {
    private Batch_Chain_Configuration__mdt config;
    private Map<String, Object> parameters;
    
    public BatchChainScheduler(Batch_Chain_Configuration__mdt config) {
        this.config = config;
        this.parameters = null;
    }
    
    public BatchChainScheduler(Batch_Chain_Configuration__mdt config, Map<String, Object> parameters) {
        this.config = config;
        this.parameters = parameters;
    }
    
    public void execute(SchedulableContext sc) {
        try {
            BatchChainExecutor.getInstance().executeBatch(config, parameters);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[BatchChainScheduler] Error executing scheduled batch: ' + config.Current_Batch__c + ' - ' + e.getMessage());
        }
    }
}