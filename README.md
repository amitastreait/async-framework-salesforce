# Salesforce Asynchronous Job Chaining Framework

A robust, configuration-driven framework for chaining Batch and Queueable jobs in Salesforce with support for parameters, error handling, and delayed execution.

## Overview

This framework provides a flexible solution for orchestrating complex asynchronous job workflows in Salesforce. It allows you to chain multiple Batch or Queueable jobs together using Custom Metadata configuration, eliminating the need for hardcoded job dependencies.

## Features

- **Metadata-Driven Configuration**: Configure job chains through Custom Metadata without code changes
- **Batch Job Chaining**: Automatically chain multiple batch jobs with configurable execution delays
- **Queueable Job Chaining**: Chain queueable jobs with finalizer support for enhanced error handling
- **Parameter Passing**: Pass runtime parameters between jobs in the chain
- **Delayed Execution**: Schedule jobs with configurable delays
- **Error Handling**: Built-in error handling and failure recovery mechanisms
- **Singleton Pattern**: Ensures efficient resource usage and prevents duplicate executions
- **Flexible Batch Sizing**: Configure batch sizes per job

## Architecture

### Core Components

#### 1. Batch Chain Executor
**[BatchChainExecutor.cls](main/default/classes/BatchChainExecutor.cls)**
- Main executor for batch job chaining
- Manages batch lifecycle and chain continuation
- Supports parameter passing between batches
- Handles delayed execution and scheduling

#### 2. Queueable Chain Executor
**[QueueableChainExecutor.cls](main/default/classes/QueueableChainExecutor.cls)**
- Main executor for queueable job chaining
- Supports finalizer-based chain continuation
- Manages runtime parameters
- Provides resilient error handling

#### 3. Interfaces

**[IBatchChainable.cls](main/default/classes/IBatchChainable.cls)**
```apex
public interface IBatchChainable {
    Batch_Chain_Configuration__mdt getBatchConfig();
    void onBeforeExecution(Map<String, Object> parameters);
    void onAfterExecution(AsyncApexJob result);
    String getCurrentBatchName();
    void initializeWithParameters(Map<String, Object> parameters);
}
```

**[IQueueableChainable.cls](main/default/classes/IQueueableChainable.cls)**
```apex
public interface IQueueableChainable {
    Queueable_Chain_Config__mdt getQueueableConfig();
    void onBeforeExecution();
    void onAfterExecution(Id jobId);
    String getCurrentQueueableName();
    void onExecutionError(Exception e);
    void onFinalizerComplete(System.FinalizerContext result);
    void setRuntimeParameters(Map<String, Object> runtimeParameters);
    Map<String, Object> getEffectiveParameters();
}
```

#### 4. Supporting Classes

- **[BatchChainScheduler.cls](main/default/classes/BatchChainScheduler.cls)**: Schedulable wrapper for delayed batch execution
- **[ResilientQueueable.cls](main/default/classes/ResilientQueueable.cls)**: Example implementation with error handling
- **[QueueableChainFinalizer.cls](main/default/classes/QueueableChainFinalizer.cls)**: Finalizer for queueable chain continuation

### Custom Metadata Types

#### Batch_Chain_Configuration__mdt
Configures batch job chains with the following fields:
- `Current_Batch__c`: Current batch class name
- `Next_Batch__c`: Next batch to execute in the chain
- `Batch_Size__c`: Number of records per batch
- `Execution_Delay__c`: Delay in minutes before execution
- `Is_Active__c`: Enable/disable the configuration
- `Max_Retries__c`: Maximum retry attempts
- `Description__c`: Configuration description

#### Queueable_Chain_Config__mdt
Configures queueable job chains with the following fields:
- `Current_Queueable__c`: Current queueable class name
- `Next_Queueable__c`: Next queueable to execute
- `Execution_Delay__c`: Delay in minutes before execution
- `Is_Active__c`: Enable/disable the configuration
- `Continue_On_Failure__c`: Continue chain even if job fails
- `Use_Finalizer__c`: Use finalizer for chain continuation
- `Max_Retries__c`: Maximum retry attempts
- `Description__c`: Configuration description

## Usage

### Batch Job Chain Example

#### 1. Implement the IBatchChainable Interface

```apex
public class MyBatchJob implements Database.Batchable<SObject>, IBatchChainable {
    private Map<String, Object> batchParameters;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        onBeforeExecution(batchParameters);
        return Database.getQueryLocator('SELECT Id, Name FROM Account LIMIT 100');
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        // Process records
        Boolean debugMode = batchParameters?.get('debugMode') == true;
        for (SObject record : scope) {
            if (debugMode) {
                System.debug('Processing: ' + record);
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        AsyncApexJob job = [SELECT Id, Status, NumberOfErrors
                           FROM AsyncApexJob WHERE Id = :bc.getJobId()];
        onAfterExecution(job);

        // Continue chain with parameters
        Map<String, Object> nextParams = new Map<String, Object>{
            'previousJobId' => job.Id
        };
        BatchChainExecutor.getInstance().continueChain(
            getCurrentBatchName(), job, nextParams
        );
    }

    public Batch_Chain_Configuration__mdt getBatchConfig() {
        return BatchChainExecutor.getInstance().getBatchConfig(getCurrentBatchName());
    }

    public void onBeforeExecution(Map<String, Object> parameters) {
        System.debug('Starting batch execution');
    }

    public void onAfterExecution(AsyncApexJob result) {
        System.debug('Batch completed: ' + result.Status);
    }

    public String getCurrentBatchName() {
        return String.valueOf(this).split(':')[0];
    }

    public void initializeWithParameters(Map<String, Object> parameters) {
        this.batchParameters = parameters;
    }
}
```

#### 2. Configure Custom Metadata

Create a `Batch_Chain_Configuration__mdt` record:
- **Developer Name**: MyBatchJob
- **Current_Batch__c**: MyBatchJob
- **Next_Batch__c**: MyNextBatchJob (or blank for end of chain)
- **Batch_Size__c**: 200
- **Execution_Delay__c**: 0
- **Is_Active__c**: true

#### 3. Start the Batch Chain

```apex
// Without parameters
Id jobId = BatchChainExecutor.getInstance().startBatch('MyBatchJob');

// With parameters
Map<String, Object> params = new Map<String, Object>{
    'debugMode' => true,
    'recordLimit' => 500
};
Id jobId = BatchChainExecutor.getInstance().startBatch('MyBatchJob', params);
```

### Queueable Job Chain Example

#### 1. Implement the IQueueableChainable Interface

```apex
public class MyQueueableJob implements System.Queueable, IQueueableChainable {
    private Map<String, Object> runtimeParameters;

    public void execute(QueueableContext context) {
        try {
            onBeforeExecution();
            // Process data
            processRecords();
            onAfterExecution(context.getJobId());

            // Continue chain
            QueueableChainExecutor.getInstance().continueChain(
                getCurrentQueueableName(), context.getJobId()
            );
        } catch (Exception e) {
            onExecutionError(e);
            throw e;
        }
    }

    private void processRecords() {
        Map<String, Object> params = getEffectiveParameters();
        Integer recordLimit = (Integer) params.get('recordLimit');
        // Processing logic
    }

    public void setRuntimeParameters(Map<String, Object> runtimeParameters) {
        this.runtimeParameters = runtimeParameters;
    }

    public Map<String, Object> getEffectiveParameters() {
        return runtimeParameters != null ? runtimeParameters : new Map<String, Object>();
    }

    // Other interface methods...
}
```

#### 2. Configure Custom Metadata

Create a `Queueable_Chain_Config__mdt` record:
- **Developer Name**: MyQueueableJob
- **Current_Queueable__c**: MyQueueableJob
- **Next_Queueable__c**: MyNextQueueableJob
- **Use_Finalizer__c**: true
- **Continue_On_Failure__c**: false
- **Is_Active__c**: true

#### 3. Start the Queueable Chain

```apex
// Without parameters
Id jobId = QueueableChainExecutor.getInstance().startQueueable('MyQueueableJob');

// With runtime parameters
Map<String, Object> params = new Map<String, Object>{
    'recordLimit' => 100,
    'processingMode' => 'intensive'
};
Id jobId = QueueableChainExecutor.getInstance().startQueueable('MyQueueableJob', params);
```

## Sample Implementations

The framework includes sample implementations demonstrating best practices:

- **[SampleBatch1.cls](main/default/classes/SampleBatch1.cls)**: Basic batch with parameter handling
- **[SampleBatch2.cls](main/default/classes/SampleBatch2.cls)**: Intermediate batch in a chain
- **[SampleBatch3.cls](main/default/classes/SampleBatch3.cls)**: Final batch in a chain
- **[SampleQueueable1.cls](main/default/classes/SampleQueueable1.cls)**: Basic queueable implementation
- **[ResilientQueueable.cls](main/default/classes/ResilientQueueable.cls)**: Error-resilient queueable with finalizer

## Testing

The framework includes comprehensive test classes:

- **[BatchChainExecutorTest.cls](main/default/classes/BatchChainExecutorTest.cls)**: Tests for batch chaining
- **[QueueableChainExecutorTest.cls](main/default/classes/QueueableChainExecutorTest.cls)**: Tests for queueable chaining

Run tests using:
```bash
sf apex run test --test-level RunLocalTests --wait 10
```

## Deployment

### Using Salesforce CLI

```bash
# Deploy the framework
sf project deploy start --source-dir frameworks/

# Deploy to specific org
sf project deploy start --source-dir frameworks/ --target-org myorg
```

### Package Contents

- **Classes**: 15+ Apex classes and interfaces
- **Custom Metadata Types**: 2 types with sample configurations
- **Test Classes**: Comprehensive test coverage

## Best Practices

1. **Always implement the appropriate interface** (`IBatchChainable` or `IQueueableChainable`) for your jobs
2. **Use Custom Metadata** for configuration instead of hardcoding job dependencies
3. **Pass parameters** between jobs to maintain context and state
4. **Handle errors gracefully** using the `onExecutionError` callback
5. **Use finalizers** for queueable jobs to ensure chain continuation even on failure
6. **Configure appropriate delays** to manage governor limits
7. **Set realistic batch sizes** based on your data volume and processing complexity
8. **Test thoroughly** with various scenarios including failures

## Governor Limits Considerations

- Maximum of 5 batch jobs can be queued or active concurrently
- Maximum of 50 queueable jobs can be enqueued in a single transaction
- Use execution delays to manage concurrent job limits
- Monitor Async Apex job queue regularly

## Error Handling

The framework provides multiple layers of error handling:

1. **Job-level**: Use `onExecutionError` callback
2. **Chain-level**: Configure `Continue_On_Failure__c` for resilient chains
3. **Finalizers**: Queueable jobs can use finalizers to handle failures
4. **Logging**: Built-in debug logging for troubleshooting
