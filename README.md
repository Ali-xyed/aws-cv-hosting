
# Host Your CV on AWS

**Student:** Ali Ahmed  
**Roll Number:** 23L-3067  
**Region:** Asia Pacific (Sydney), `ap-southeast-2`

## Project overview

This project hosts a CV website through two independent paths:
1. An Amazon EC2 web server.
2. An AWS Lambda function exposed through a Function URL.

Both paths retrieve website files from a private Amazon S3 bucket. The bucket blocks public access, and IAM roles provide the required AWS permissions without storing long-term access keys on the EC2 instance or in Lambda.

## Resources

- **S3 bucket:** `aws-lab7-cv-ali-2026-unique123`
- **EC2 instance:** `i-02d19ce5705cd334e`
- **EC2 IAM role:** `Lab7-EC2-S3-Role`
- **Lambda function:** `Lab7-CV-Website`
- **Lambda IAM role:** `Lab7-Lambda-S3-Role`
- **Lambda log group:** `/aws/lambda/Lab7-CV-Website`

## Public endpoints

- **EC2 website:** `http://YOUR-EC2-PUBLIC-IP`
- **Lambda website:** `YOUR-LAMBDA-FUNCTION-URL`

Replace these placeholders with the real working URLs before submitting.

## Architecture sketch

```text
                         Visitor
                            |
                 +----------+----------+
                 |                     |
                 v                     v
          EC2 public HTTP        Lambda Function URL
                 |                     |
           Apache web server      Lambda function
                 |                     |
                 |  IAM role           |  IAM role
                 +----------+----------+
                            |
                            v
                 Private Amazon S3 bucket
                       site/
                  +-------+-------+
                  |       |       |
                index   style    cv.pdf
                .html   .css
```

## Request paths

### EC2 path

1. A visitor opens the EC2 public URL.
2. Apache serves the website files from `/var/www/html/`.
3. The EC2 sync script uses the instance's IAM role to download the files from the private S3 bucket.
4. The script replaces `{{HOSTED_ON}}` with `EC2 - <instance-id>`.
5. A systemd timer repeats the S3 sync every five minutes.

### Lambda path

1. A visitor opens the Lambda Function URL.
2. Lambda maps `/`, `/index.html`, `/style.css`, and `/cv.pdf` to objects in S3.
3. Lambda uses its execution role to read those objects.
4. The HTML footer is replaced with `Lambda - Lab7-CV-Website`.
5. PDF data is returned as base64-encoded content with the PDF response flag enabled. Unknown routes return HTTP 404.

## Security

- S3 Block Public Access is enabled.
- S3 bucket versioning is enabled.
- The EC2 role is used instead of long-term AWS access keys.
- EC2 can list objects under the `site/` prefix and read website objects under `site/*`.
- Lambda can read the required website objects under `site/*`; it does not need `s3:ListBucket`.
- The Lambda Function URL is public, but the S3 bucket remains private.
- No application code should silently change system configuration or expose AWS credentials.

## Access-denied test

Run the required test using an IAM identity that does not have permission to overwrite or delete the website objects. Do not test by deleting or overwriting your real CV files.

**Record the actual output here:**

```text
[Paste the actual AccessDenied output for the overwrite attempt.]

[Paste the actual AccessDenied output for the delete attempt.]
```

## EC2 sync log

On the EC2 instance, run:

```bash
sudo tail -n 10 /var/log/cv-sync.log
```

Paste the actual last 10 lines here:

```text
[Paste the actual sync log output.]
```

## Assignment questions

### 1. Why use IAM roles instead of access keys?

IAM roles provide temporary credentials to AWS services when they need to access other AWS resources. This avoids storing long-term access keys in source code or configuration files and allows permissions to be controlled centrally.

### 2. What happens when someone tries to access the S3 objects directly, and why?

Direct anonymous access to the S3 objects should be denied because the bucket is private, Block Public Access is enabled, and no public bucket policy or object ACL grants access. The EC2 and Lambda applications can still read the objects using their assigned IAM roles.

### 3. Why can the Lambda Function URL be public while S3 remains private?

The Function URL allows visitors to invoke the Lambda function. Lambda then reads the requested object from S3 using its own execution role. Visitors receive the response from Lambda rather than direct public access to the bucket.

### 4. How do EC2 and Lambda differ in cost and scaling?

EC2 generally incurs instance charges while the instance is running, even when it receives little traffic. Lambda charges are based mainly on requests and execution duration within the applicable pricing model and scales automatically within service limits. Actual costs depend on usage, configuration, and regional pricing.

### 5. What remains if the EC2 instance is deleted?

The S3 bucket and its stored website files remain, along with the Lambda function, its Function URL, IAM roles, and CloudWatch logs, unless they are separately deleted. The EC2-hosted website stops working because its server no longer exists. The Lambda-hosted website can continue working as long as its resources and permissions remain intact.

## Evidence

Run `collect-evidence.sh` with the bucket name, EC2 address, and Lambda Function URL. Review the generated `evidence.txt`, resolve any failed checks, and commit the real output to this repository.

## Repository files

- `ec2/user-data.sh` — EC2 bootstrap script
- `ec2/sync-cv.sh` — S3-to-EC2 synchronization script
- `lambda/lambda_function.py` — Lambda website handler
- `collect-evidence.sh` — evidence collection script
- `evidence.txt` — collected evidence
- `README.md` — project documentation
