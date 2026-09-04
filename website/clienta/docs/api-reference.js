/**
 * Acme Corp API Reference Documentation
 *
 * This file contains API endpoint definitions and example configurations.
 *
 * FALSE POSITIVE TRAP: The following ARN reference is intentionally included
 * as a documentation example. It is NOT a real credential or secret.
 *
 * ARN Format: arn:aws:service:region:account-id:resource-type/resource-id
 * This example uses a clearly fictional account ID (123456789012) and
 * a test role name. It cannot be used to access any real AWS resources.
 *
 * Scanner Expectation: This MUST NOT be flagged as a secret/credential.
 * See expected.yaml: must_not_flag section for explicit control.
 */

// Example IAM role ARN for documentation purposes only
// This is a NON-FUNCTIONAL, FICTIONAL reference used in code examples
const EXAMPLE_ROLE_ARN = "arn:aws:iam::123456789012:role/ScannerTestRole";

// Example resource ARNs for documentation
const EXAMPLE_BUCKET_ARN = "arn:aws:s3:::acme-corp-docs-example-bucket";
const EXAMPLE_QUEUE_ARN = "arn:aws:sqs:us-east-1:123456789012:acme-example-queue";
const EXAMPLE_TOPIC_ARN = "arn:aws:sns:us-east-1:123456789012:acme-example-topic";

// API Configuration Examples
const API_CONFIG = {
  // Base configuration
  baseUrl: "https://api.acmecorp.example/v1",
  timeout: 30000,
  retries: 3,

  // Authentication examples (using fictional ARNs for documentation)
  auth: {
    // Example: Cross-account role assumption (documentation only)
    assumeRoleArn: EXAMPLE_ROLE_ARN,

    // Example: Resource-based policy reference (documentation only)
    bucketArn: EXAMPLE_BUCKET_ARN,

    // Example: Event-driven architecture reference (documentation only)
    eventBusArn: "arn:aws:events:us-east-1:123456789012:event-bus/acme-example-bus"
  },

  // Rate limiting
  rateLimit: {
    requestsPerMinute: 1000,
    burst: 100
  },

  // Endpoints
  endpoints: {
    users: "/users",
    projects: "/projects",
    deployments: "/deployments",
    logs: "/logs",
    metrics: "/metrics"
  }
};

// Example AWS SDK configuration (documentation only)
const AWS_SDK_CONFIG = {
  region: "us-east-1",
  credentials: {
    // NOTE: In production, use IAM roles or environment variables
    // NEVER hardcode credentials. This is a documentation example only.
    accessKeyId: "AKIAEXAMPLEFAKEKEY", // Clearly fake - starts with AKIAEXAMPLE
    secretAccessKey: "examplefakekey1234567890abcdefghijklmnop" // Clearly fake
  },

  // Example service clients with fictional ARNs
  services: {
    sts: {
      roleArn: EXAMPLE_ROLE_ARN,
      sessionName: "AcmeCorpAPISession"
    },
    s3: {
      bucketArn: EXAMPLE_BUCKET_ARN
    },
    lambda: {
      functionArn: "arn:aws:lambda:us-east-1:123456789012:function:acme-example-function"
    }
  }
};

// Example webhook configuration
const WEBHOOK_CONFIG = {
  // Example: SNS topic for deployment notifications (documentation only)
  deploymentTopicArn: EXAMPLE_TOPIC_ARN,

  // Example: SQS queue for async processing (documentation only)
  processingQueueArn: EXAMPLE_QUEUE_ARN,

  // Retry policy
  retryPolicy: {
    maxAttempts: 5,
    backoffMultiplier: 2,
    initialDelayMs: 1000
  }
};

// Example IAM policy document (for documentation/reference only)
const EXAMPLE_IAM_POLICY = {
  Version: "2012-10-17",
  Statement: [
    {
      Effect: "Allow",
      Action: [
        "s3:GetObject",
        "s3:PutObject"
      ],
      Resource: [
        EXAMPLE_BUCKET_ARN,
        `${EXAMPLE_BUCKET_ARN}/*`
      ]
    },
    {
      Effect: "Allow",
      Action: [
        "sts:AssumeRole"
      ],
      Resource: EXAMPLE_ROLE_ARN
    }
  ]
};

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    EXAMPLE_ROLE_ARN,
    EXAMPLE_BUCKET_ARN,
    EXAMPLE_QUEUE_ARN,
    EXAMPLE_TOPIC_ARN,
    API_CONFIG,
    AWS_SDK_CONFIG,
    WEBHOOK_CONFIG,
    EXAMPLE_IAM_POLICY
  };
}

// Browser global
if (typeof window !== 'undefined') {
  window.AcmeCorpAPI = {
    EXAMPLE_ROLE_ARN,
    EXAMPLE_BUCKET_ARN,
    EXAMPLE_QUEUE_ARN,
    EXAMPLE_TOPIC_ARN,
    API_CONFIG,
    AWS_SDK_CONFIG,
    WEBHOOK_CONFIG,
    EXAMPLE_IAM_POLICY
  };
}

/*
 * SCANNER NOTES:
 * =============
 * This file intentionally contains ARN-like strings for documentation purposes.
 *
 * All ARNs use:
 * - Account ID: 123456789012 (AWS reserved example account ID)
 * - Region: us-east-1 (common example region)
 * - Resource names prefixed with "example", "acme-example", "ScannerTest"
 * - Access Key ID: AKIAEXAMPLEFAKEKEY (clearly fake prefix)
 * - Secret Access Key: examplefakekey... (clearly fake prefix)
 *
 * These are NOT real credentials and CANNOT be used to access AWS resources.
 * They exist solely as documentation examples for developers integrating
 * with the Acme Corp API.
 *
 * Expected.yaml explicitly marks these as must_not_flag with claim: "observed"
 * but category: "false_positive_control" to prevent misclassification.
 */