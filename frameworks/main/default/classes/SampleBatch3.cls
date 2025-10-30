/**
 * Sample third batch class in the chain with generic parameter support
 */
public class SampleBatch3 implements Database.Batchable<SObject>, IBatchChainable {
    private Map<String, Object> batchParameters;
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        onBeforeExecution(batchParameters);
        
        String queryString = 'SELECT Id, Name FROM Opportunity LIMIT 50';
        
        return Database.getQueryLocator(queryString);
    }
    
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        System.debug('Executing SampleBatch3 with ' + scope.size() + ' records');
        
        Boolean debugMode = batchParameters != null && batchParameters.containsKey('debugMode') ? 
                           (Boolean) batchParameters.get('debugMode') : false;
        
        if (batchParameters != null) {
            if (batchParameters.containsKey('processedRecords')) {
                System.debug('Batch1 processed ' + batchParameters.get('processedRecords') + ' records');
            }
            if (batchParameters.containsKey('batch2ProcessedRecords')) {
                System.debug('Batch2 processed ' + batchParameters.get('batch2ProcessedRecords') + ' records');
            }
        }
        
        for (SObject record : scope) {
            Opportunity opp = (Opportunity) record;
            if (debugMode) {
                System.debug('Processing Opportunity: ' + opp.Name);
            }
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, TotalJobItems, JobItemsProcessed
            FROM AsyncApexJob 
            WHERE Id = :bc.getJobId()
        ];
        
        onAfterExecution(job);
        
        System.debug('Chain completed! Final batch processed ' + job.JobItemsProcessed + ' records');
        
        BatchChainExecutor.getInstance().continueChain(getCurrentBatchName(), job);
    }
    
    public Batch_Chain_Configuration__mdt getBatchConfig() {
        return BatchChainExecutor.getInstance().getBatchConfig(getCurrentBatchName());
    }
    
    public void onBeforeExecution(Map<String, Object> parameters) {
        System.debug('SampleBatch3: Starting execution (Final batch)');
        if (parameters != null) {
            System.debug('SampleBatch3: Parameters received: ' + parameters.keySet());
        }
    }
    
    public void onAfterExecution(AsyncApexJob result) {
        System.debug('SampleBatch3: Completed with status: ' + result.Status);
        System.debug('SampleBatch3: Final batch - Chain execution completed!');
    }
    
    public String getCurrentBatchName() {
        return String.valueOf(this).split(':')[0];
    }
    
    public void initializeWithParameters(Map<String, Object> parameters) {
        this.batchParameters = parameters;
    }
}