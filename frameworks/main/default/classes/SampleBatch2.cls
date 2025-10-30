/**
 * Sample second batch class in the chain with generic parameter support
 */
public class SampleBatch2 implements Database.Batchable<SObject>, IBatchChainable {
    private Map<String, Object> batchParameters;
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        onBeforeExecution(batchParameters);
        
        String queryString = 'SELECT Id, Name FROM Contact LIMIT 100';
        
        return Database.getQueryLocator(queryString);
    }
    
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        System.debug('Executing SampleBatch2 with ' + scope.size() + ' records');
        
        Boolean debugMode = batchParameters != null && batchParameters.containsKey('debugMode') ? 
                           (Boolean) batchParameters.get('debugMode') : false;
        
        if (batchParameters != null && batchParameters.containsKey('processedRecords')) {
            System.debug('Previous batch processed ' + batchParameters.get('processedRecords') + ' records');
        }
        
        for (SObject record : scope) {
            Contact con = (Contact) record;
            if (debugMode) {
                System.debug('Processing Contact: ' + con.Name);
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
        
        Map<String, Object> nextBatchParams = new Map<String, Object>();
        if (batchParameters != null) {
            nextBatchParams.putAll(batchParameters);
        }
        nextBatchParams.put('batch2ProcessedRecords', job.JobItemsProcessed);
        
        BatchChainExecutor.getInstance().continueChain(getCurrentBatchName(), job, nextBatchParams);
    }
    
    public Batch_Chain_Configuration__mdt getBatchConfig() {
        return BatchChainExecutor.getInstance().getBatchConfig(getCurrentBatchName());
    }
    
    public void onBeforeExecution(Map<String, Object> parameters) {
        System.debug('SampleBatch2: Starting execution');
        if (parameters != null) {
            System.debug('SampleBatch2: Parameters received: ' + parameters.keySet());
        }
    }
    
    public void onAfterExecution(AsyncApexJob result) {
        System.debug('SampleBatch2: Completed with status: ' + result.Status);
        System.debug('SampleBatch2: Processed: ' + result.JobItemsProcessed + '/' + result.TotalJobItems);
    }
    
    public String getCurrentBatchName() {
        return String.valueOf(this).split(':')[0];
    }
    
    public void initializeWithParameters(Map<String, Object> parameters) {
        this.batchParameters = parameters;
    }
}