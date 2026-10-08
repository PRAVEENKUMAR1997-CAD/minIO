# MinIO S3 Platform - Integration Guide

## Overview

This guide covers integrating applications with the MinIO S3 Platform.

## Endpoint Information

| Service | URL | Purpose |
|---------|-----|---------|
| S3 API | http://localhost:9000 | Object storage API |
| Console | http://localhost:9001 | Web administration |

## AWS CLI Integration

### Installation

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify
aws --version
```

### Configuration

#### Method 1: AWS Configure

```bash
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: us-east-1
# Default output format: json
```

#### Method 2: Environment Variables

```bash
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_DEFAULT_REGION=us-east-1
```

#### Method 3: Named Profile

```ini
# ~/.aws/credentials
[minio]
aws_access_key_id = your-access-key
aws_secret_access_key = your-secret-key

# ~/.aws/config
[profile minio]
region = us-east-1
output = json
```

### Usage Examples

```bash
# List buckets
aws --endpoint-url http://localhost:9000 s3 ls

# List bucket contents
aws --endpoint-url http://localhost:9000 s3 ls s3://developer-data/

# Upload file
aws --endpoint-url http://localhost:9000 s3 cp myfile.txt s3://developer-data/

# Upload directory
aws --endpoint-url http://localhost:9000 s3 cp mydir/ s3://developer-data/mydir/ --recursive

# Download file
aws --endpoint-url http://localhost:9000 s3 cp s3://developer-data/myfile.txt ./

# Sync directory
aws --endpoint-url http://localhost:9000 s3 sync ./local-dir s3://developer-data/remote-dir/

# Delete file
aws --endpoint-url http://localhost:9000 s3 rm s3://developer-data/myfile.txt

# Get object info
aws --endpoint-url http://localhost:9000 s3api head-object \
  --bucket developer-data \
  --key myfile.txt
```

### Using Named Profile

```bash
aws --endpoint-url http://localhost:9000 --profile minio s3 ls
```

### Shell Alias (Recommended)

```bash
# Add to ~/.bashrc or ~/.zshrc
alias s3='aws --endpoint-url http://localhost:9000 s3'
alias s3api='aws --endpoint-url http://localhost:9000 s3api'

# Usage
s3 ls
s3 cp file.txt s3://developer-data/
```

## Java / Spring Boot Integration

### Dependencies

**Maven (pom.xml):**

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>bom</artifactId>
            <version>2.25.0</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>

<dependencies>
    <dependency>
        <groupId>software.amazon.awssdk</groupId>
        <artifactId>s3</artifactId>
    </dependency>
</dependencies>
```

**Gradle (build.gradle):**

```groovy
implementation platform('software.amazon.awssdk:bom:2.25.0')
implementation 'software.amazon.awssdk:s3'
```

### Configuration Properties

**application.yml:**

```yaml
minio:
  endpoint: http://localhost:9000
  region: us-east-1
  bucket: developer-data
  access-key: ${MINIO_ACCESS_KEY}
  secret-key: ${MINIO_SECRET_KEY}
```

**application.properties:**

```properties
minio.endpoint=http://localhost:9000
minio.region=us-east-1
minio.bucket=developer-data
minio.access-key=${MINIO_ACCESS_KEY}
minio.secret-key=${MINIO_SECRET_KEY}
```

### S3 Client Configuration

```java
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.net.URI;

@Configuration
public class S3Config {

    @Value("${minio.endpoint}")
    private String endpoint;

    @Value("${minio.region}")
    private String region;

    @Value("${minio.access-key}")
    private String accessKey;

    @Value("${minio.secret-key}")
    private String secretKey;

    @Bean
    public S3Client s3Client() {
        AwsBasicCredentials credentials = AwsBasicCredentials.create(
            accessKey,
            secretKey
        );

        S3Configuration s3Config = S3Configuration.builder()
            .pathStyleAccessEnabled(true)  // Required for MinIO
            .build();

        return S3Client.builder()
            .endpointOverride(URI.create(endpoint))
            .region(Region.of(region))
            .credentialsProvider(StaticCredentialsProvider.create(credentials))
            .serviceConfiguration(s3Config)
            .build();
    }
}
```

### Service Implementation

```java
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.core.sync.ResponseTransformer;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.InputStream;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class StorageService {

    private final S3Client s3Client;
    private final String bucket;

    public StorageService(S3Client s3Client, 
                          @Value("${minio.bucket}") String bucket) {
        this.s3Client = s3Client;
        this.bucket = bucket;
    }

    /**
     * Upload a file to S3
     */
    public void upload(String key, byte[] content, String contentType) {
        PutObjectRequest request = PutObjectRequest.builder()
            .bucket(bucket)
            .key(key)
            .contentType(contentType)
            .build();

        s3Client.putObject(request, RequestBody.fromBytes(content));
    }

    /**
     * Upload from InputStream
     */
    public void upload(String key, InputStream inputStream, 
                       long contentLength, String contentType) {
        PutObjectRequest request = PutObjectRequest.builder()
            .bucket(bucket)
            .key(key)
            .contentType(contentType)
            .contentLength(contentLength)
            .build();

        s3Client.putObject(request, RequestBody.fromInputStream(inputStream, contentLength));
    }

    /**
     * Download a file from S3
     */
    public byte[] download(String key) {
        GetObjectRequest request = GetObjectRequest.builder()
            .bucket(bucket)
            .key(key)
            .build();

        return s3Client.getObjectAsBytes(request).asByteArray();
    }

    /**
     * Download to InputStream
     */
    public InputStream downloadStream(String key) {
        GetObjectRequest request = GetObjectRequest.builder()
            .bucket(bucket)
            .key(key)
            .build();

        return s3Client.getObject(request, ResponseTransformer.toInputStream());
    }

    /**
     * List objects in bucket
     */
    public List<String> listObjects(String prefix) {
        ListObjectsV2Request request = ListObjectsV2Request.builder()
            .bucket(bucket)
            .prefix(prefix)
            .build();

        return s3Client.listObjectsV2(request)
            .contents()
            .stream()
            .map(S3Object::key)
            .collect(Collectors.toList());
    }

    /**
     * Delete an object
     */
    public void delete(String key) {
        DeleteObjectRequest request = DeleteObjectRequest.builder()
            .bucket(bucket)
            .key(key)
            .build();

        s3Client.deleteObject(request);
    }

    /**
     * Check if object exists
     */
    public boolean exists(String key) {
        try {
            HeadObjectRequest request = HeadObjectRequest.builder()
                .bucket(bucket)
                .key(key)
                .build();
            
            s3Client.headObject(request);
            return true;
        } catch (NoSuchKeyException e) {
            return false;
        }
    }

    /**
     * Generate pre-signed URL for download
     */
    public String generatePresignedUrl(String key, int expirationMinutes) {
        // For pre-signed URLs, use S3Presigner
        // See AWS SDK documentation for implementation
        throw new UnsupportedOperationException("Implement with S3Presigner");
    }
}
```

### Controller Example

```java
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.List;

@RestController
@RequestMapping("/api/files")
public class FileController {

    private final StorageService storageService;

    public FileController(StorageService storageService) {
        this.storageService = storageService;
    }

    @PostMapping("/upload")
    public ResponseEntity<String> upload(@RequestParam("file") MultipartFile file) 
            throws IOException {
        String key = "uploads/" + file.getOriginalFilename();
        
        storageService.upload(
            key,
            file.getBytes(),
            file.getContentType()
        );
        
        return ResponseEntity.ok("Uploaded: " + key);
    }

    @GetMapping("/download/{key}")
    public ResponseEntity<byte[]> download(@PathVariable String key) {
        byte[] content = storageService.download("uploads/" + key);
        
        return ResponseEntity.ok()
            .contentType(MediaType.APPLICATION_OCTET_STREAM)
            .body(content);
    }

    @GetMapping("/list")
    public ResponseEntity<List<String>> list(
            @RequestParam(defaultValue = "") String prefix) {
        return ResponseEntity.ok(storageService.listObjects(prefix));
    }

    @DeleteMapping("/{key}")
    public ResponseEntity<Void> delete(@PathVariable String key) {
        storageService.delete("uploads/" + key);
        return ResponseEntity.noContent().build();
    }
}
```

## Python Integration

### Installation

```bash
pip install boto3
```

### Configuration

```python
import boto3
from botocore.config import Config

s3_client = boto3.client(
    's3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id='your-access-key',
    aws_secret_access_key='your-secret-key',
    region_name='us-east-1',
    config=Config(signature_version='s3v4')
)
```

### Usage Examples

```python
# Upload file
s3_client.upload_file('local-file.txt', 'developer-data', 'remote-file.txt')

# Download file
s3_client.download_file('developer-data', 'remote-file.txt', 'local-file.txt')

# List objects
response = s3_client.list_objects_v2(Bucket='developer-data')
for obj in response.get('Contents', []):
    print(obj['Key'])

# Delete object
s3_client.delete_object(Bucket='developer-data', Key='remote-file.txt')
```

## Node.js Integration

### Installation

```bash
npm install @aws-sdk/client-s3
```

### Configuration

```javascript
const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');

const s3Client = new S3Client({
    endpoint: 'http://localhost:9000',
    region: 'us-east-1',
    credentials: {
        accessKeyId: 'your-access-key',
        secretAccessKey: 'your-secret-key'
    },
    forcePathStyle: true  // Required for MinIO
});
```

### Usage Examples

```javascript
// Upload
const uploadCommand = new PutObjectCommand({
    Bucket: 'developer-data',
    Key: 'my-file.txt',
    Body: Buffer.from('Hello, World!')
});
await s3Client.send(uploadCommand);

// Download
const getCommand = new GetObjectCommand({
    Bucket: 'developer-data',
    Key: 'my-file.txt'
});
const response = await s3Client.send(getCommand);
const content = await response.Body.transformToString();
```

## Go Integration

### Installation

```bash
go get github.com/aws/aws-sdk-go-v2
go get github.com/aws/aws-sdk-go-v2/config
go get github.com/aws/aws-sdk-go-v2/service/s3
```

### Configuration

```go
package main

import (
    "context"
    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/credentials"
    "github.com/aws/aws-sdk-go-v2/service/s3"
)

func newS3Client() *s3.Client {
    customResolver := aws.EndpointResolverWithOptionsFunc(
        func(service, region string, options ...interface{}) (aws.Endpoint, error) {
            return aws.Endpoint{
                URL:           "http://localhost:9000",
                SigningRegion: "us-east-1",
            }, nil
        })

    cfg, _ := config.LoadDefaultConfig(context.TODO(),
        config.WithEndpointResolverWithOptions(customResolver),
        config.WithCredentialsProvider(
            credentials.NewStaticCredentialsProvider(
                "your-access-key",
                "your-secret-key",
                "",
            ),
        ),
    )

    return s3.NewFromConfig(cfg, func(o *s3.Options) {
        o.UsePathStyle = true
    })
}
```

## Testing Integration

### Verify Connection

```bash
# Quick test
aws --endpoint-url http://localhost:9000 s3 ls

# Upload test file
echo "test" | aws --endpoint-url http://localhost:9000 s3 cp - s3://developer-data/test.txt

# Verify upload
aws --endpoint-url http://localhost:9000 s3 ls s3://developer-data/

# Download and verify
aws --endpoint-url http://localhost:9000 s3 cp s3://developer-data/test.txt -

# Cleanup
aws --endpoint-url http://localhost:9000 s3 rm s3://developer-data/test.txt
```

## Troubleshooting

### Connection Refused

```
Could not connect to the endpoint URL
```

**Solution:** Verify MinIO is running and endpoint URL is correct.

### Access Denied

```
An error occurred (AccessDenied): Access Denied
```

**Solution:** Check credentials and user permissions.

### Signature Mismatch

```
The request signature we calculated does not match
```

**Solution:** Verify secret key and ensure path-style access is enabled.

## Related Documentation

- [Credentials](credentials.md)
- [Setup](setup.md)
- [Security](security.md)
