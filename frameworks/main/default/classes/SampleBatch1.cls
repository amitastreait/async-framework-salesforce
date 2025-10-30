/**
 * Sample batch class implementing IBatchChainable with generic parameter support
 *  Map<String, Object> params = new Map<String, Object>();
    params.put('debugMode', true);
    Id jobId = executor.startBatch('SampleBatch1', params);
 */
public class SampleBatch1 implements Database.Batchable<SObject>, IBatchChainable {
    private Map<String, Object> batchParameters;
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        onBeforeExecution(batchParameters);
        String queryString = 'SELECT Id, Name FROM Account LIMIT 100';
        return Database.getQueryLocator(queryString);
    }
    
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        System.debug('Executing SampleBatch1 with ' + scope.size() + ' records');
        
        // Use parameters in processing if needed
        Boolean debugMode = batchParameters != null && batchParameters.containsKey('debugMode') ? (Boolean) batchParameters.get('debugMode') : false;
        
        for (SObject record : scope) {
            Account acc = (Account) record;
            if (debugMode) {
                System.debug('Processing Account: ' + acc.Name);
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
        
        // Pass parameters to next batch if needed
        Map<String, Object> nextBatchParams = new Map<String, Object>();
        if (batchParameters != null) {
            nextBatchParams.putAll(batchParameters);
        }
        nextBatchParams.put('processedRecords', job.JobItemsProcessed);
        
        BatchChainExecutor.getInstance().continueChain(getCurrentBatchName(), job, nextBatchParams);
    }
    
    // IBatchChainable implementation
    public Batch_Chain_Configuration__mdt getBatchConfig() {
        return BatchChainExecutor.getInstance().getBatchConfig(getCurrentBatchName());
    }
    
    public void onBeforeExecution(Map<String, Object> parameters) {
        System.debug('SampleBatch1: Starting execution');
        if (parameters != null) {
            System.debug('SampleBatch1: Parameters received: ' + parameters.keySet());
        }
    }
    
    public void onAfterExecution(AsyncApexJob result) {
        System.debug('SampleBatch1: Post-execution logic');
        System.debug('SampleBatch1: Status: ' + result.Status);
        System.debug('SampleBatch1: Processed: ' + result.JobItemsProcessed + '/' + result.TotalJobItems);
        System.debug('SampleBatch1: Errors: ' + result.NumberOfErrors);
    }
    
    public String getCurrentBatchName() {
        return String.valueOf(this).split(':')[0];
    }
    
    public void initializeWithParameters(Map<String, Object> parameters) {
        this.batchParameters = parameters;
    }
}