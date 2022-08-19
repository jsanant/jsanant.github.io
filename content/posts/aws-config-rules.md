---
title: "AWS Config Rules"
summary: "How different trigger types work in AWS Config"
date: 2022-02-28T20:32:58+05:30
draft: false
tags: ['AWS', 'AWS Config']
---

![config meme](/config_meme.jpeg#center)

### Introduction

> Security is a part of the business, not against it.

Auditing an environment is a daunting task no one ever wants to take up but in the era of Cloud Computing, everything is simple. In the article I will be 
explaining on how you can use AWS Config to audit your environment by creating custom rules and the important things to remember when creating them.

Let’s start auditing!

---

### Types of Config Rules

A config rule represents your desired configuration settings for specific AWS resources. If a resource violates a rule, config flags the resource and the rule as non compliant.

There are two types of rules:

- AWS Managed rules: AWS Config provides predefined rules which are customisable.
- AWS Custom rules: With AWS Config you can also create custom rules where in you have control over the logic of the rule and what violation to looks for. While AWS Config continuously tracks your resource configuration changes, it checks whether these changes violate any of the conditions in your rules.

---

### Custom Rules

When it comes to the managed rules they are a black box, you don’t have access to the lambda functions nor can you edit them since they are managed by AWS.

That’s where custom rules come to the rescue, when you want to check for a particular violation and a managed rule doesn’t get the job done then you will have to create a custom rule, custom basically means that the rule points to a lambda function and when the rule is evaluated config sends data to the lambda function for computation.

There are two ways to trigger a config rule:

- Configuration Changes (CC): Configuration change is where the configuration of a resource changes for example, the tag on a particular instance is removed or aded. There are three scope of changes which tells Config what to look for: Resources such IAM, S3 etc. Tag for resources with particular tags. All Changes for all the resources that are recorded by Config when they are created, updated or deleted.

- Periodic: Which triggers the Config rule at a desired frequency.

Important thing to remember is when to choose Configuration Changes and when to go with Periodic trigger.

Let’s take a look at the event pattern published to lambda event during a configuration change and a periodic trigger.

Event pattern published to lambda during a configuration change for a EC2 instance:

{{< highlight bash >}}
{
 "invokingEvent": "{"configurationItem": {"configurationItemCaptureTime":"2016-02 17T01:36:34.043Z","awsAccountId":"123456789012","configurationItemStatus":"OK","resourceId":"i-00000000","ARN":"arn:aws:ec2:us-east-1:123456789012:instance/i-00000000","awsRegion":"us-east-1","availabilityZone":"us-east-1a","resourceType":"AWS::EC2::Instance","tags":{"Foo":"Bar"},"relationships":[{"resourceId":"eipalloc-00000000","resourceType":"AWS::EC2::EIP","name":"Is attached to ElasticIp"}],"configuration": {"foo":"bar"}},"messageType":"ConfigurationItemChangeNotification"},
 "ruleParameters": "{"Key":"Value"}",
 "resultToken": "ResultToken",
 "eventLeftScope": false,
 "executionRoleArn": "arn:aws:iam::123456789012:role/config-role",
 "configRuleArn": "arn:aws:config:us-east-1:123456789012:config-rule/config-rule",
 "configRuleName": "change-triggered-config-rule",
 "configRuleId": "config-rule",
 "accountId": "123456789012",
 "version": "1.0"
}
{{< /highlight >}}  
When it comes to periodic trigger the event pattern that is published is:

{{< highlight bash >}}
{
    "invokingEvent": "{"awsAccountId":"123456789012","notificationCreationTime":"2016-07-13T21:50:00.373Z","messageType":"ScheduledNotification","recordVersion":"1.0"}",
    "ruleParameters": "{"Key":"Value"}",
    "resultToken": "ResultToken",
    "eventLeftScope": false,
    "executionRoleArn": "arn:aws:iam::123456789012:role/config-role",
    "configRuleArn": "arn:aws:config:us-east-1:123456789012:config-rule/config-rule",
    "configRuleName": "periodic-config-rule",
    "configRuleId": "config-rule",
    "accountId": "123456789012",
    "version": "1.0"
}
{{< /highlight >}}  


If you take a close look at the ```invokingEvent``` in the JSON object for both the event patterns you will see that the event pattern for the configuration change has the attribute ```configurationItem``` but in the event pattern for the periodic trigger the attribute ```configurationItem``` does not exist.

The attribute ```configurationItem``` mainly contains details of a particular resource it’s monitoring in our case an EC2 instance, referring back to the event pattern for a configuration change you can see details such as instance id, relationship of the instance to EIPs, tags attached to the instance but the ```invokingEvent``` in the event pattern for the periodic trigger does not have any of these values and it only has accountId, messageType which are of no use to us. [For more details on rest of the attributes in the Event Pattern.](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config_develop-rules_example-events.html)

So when it comes to using configuration change most of the work is cut out for us as config sends data about the resource we are monitoring from which we can parse the data and determine whether the rule is compliant or non compliant, if we were to use the periodic trigger we would have to make a API call to the AWS service we are checking the compliance for and send the evaluated data back to config.

The *main drawback* of using a periodic trigger is that if and when there is a change in a particular resource, config will not get triggered immediately and we wouldn’t know if there was a violation happening but we would know about it based on the frequency at which the evaluations happen which can be 1 hour, 6 hour or even the next day which is not feasible.

When it comes to configurational changes the evaluations are immediate, for example, if a user attaches a EIP to a instance making it a public instance which is meant to be private then config triggers the rule and the instance is shown as non compliant due to the violation.

Before you create a rule you can get the configuration history of a resource by using the CLI command:

{{< highlight bash >}}
aws configservice get-resource-config-history --resource-type AWS::EC2::Instance --resource-id i-00000 --region us-east-1
{{< /highlight >}}

With the generated configuration details you can develop your code locally.

Let’s take a look at a custom rule which checks if the instance is publicly accessible or not and treat a publicly accessible instance as non compliant and the trigger type of this rule is configuration changes.

- lambda_handler:

{{< gist jsanant 4b93e31b225bca2c8d7fb3284e1a8ff2 >}}
    
- In Line 5: We are parsing out the invokingEvent to get the configurationItem.

- In Line 12: Here we are checking if the resource (instance) is deleted or not, this is an important check because if the resource is deleted we wouldn’t want stale data showing up on the config dashboard so we perform this check before we compute the evaluation.


- evaluate_compliance:

{{< gist jsanant 701c72c86684c06efd710e391cb869ee >}}

- In Line 13: We are checking if the instance is publicly accessible or not.

After computation it returns the ```compliance_type``` and ```annotation``` to the ```put_evaluations()``` request.

As you can see from the two snippets above we didn’t use any [boto3]({{< relref "#word-to-the-wise" >}}) calls (Other than the ```put_evaluations()``` call to config) to the EC2 service to get details of the instance, all the data about the instance was published to lambda by config when we chose the trigger type as configuration changes.

As a exercise go ahead and create a custom rule and choose the trigger type as periodic trigger and see how different it is from configuration changes.

---

### Word to the wise:

- There are some resource specific attributes that are not monitored by Config [More details here](https://docs.aws.amazon.com/config/latest/developerguide/resource-config-reference.html). If you have a custom rule that checks if the bucket is encrypted or not you will have to use boto3 calls to fetch the details about the bucket since the AWS S3 bucket encryption is not monitored by config.

- When you are logged into the AWS Config console and you want to evaluate a rule you would essentially click on Re-Evaluate, the most important thing note here is that it causes a configuration change to occur.

- [AWS Community repo for Custom Config Rules.](https://github.com/awslabs/aws-config-rules)

---

### Since you stayed till the end you get bonus content!

![money](/money.gif#center)

[AWS Config is a costly service.](https://aws.amazon.com/config/pricing/)

#### Alternatives to AWS Config:

- [Cloud Custodian](https://github.com/cloud-custodian/cloud-custodian): It’s a open source tool by Capital One.
- [Janitor Monkey](https://github.com/Netflix/SimianArmy/wiki/Janitor-Home): A open source tool created by Netflix but it is very restrictive to the Netflix environment.
- [Security Monkey](https://github.com/Netflix/security_monkey): Another open source tool by Netflix for monitoring your environment.

---

I hope this article helped you understand how to create custom Config rules and how the different trigger types work.

Thank you for reading! Hope you enjoyed it. Appreciate your feedback.
