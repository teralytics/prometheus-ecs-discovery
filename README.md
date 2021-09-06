# Prometheus Amazon ECS discovery

Prometheus has native Amazon EC2 discovery capabilities, but it does
not have the capacity to discover ECS instances that can be scraped
by Prometheus.  This program is a Prometheus File Service Discovery
(`file_sd_config`) integration that bridges said gap.

## Help

Run `prometheus-ecs-discovery --help` to get information.

The command line parameters that can be used are:

* -config.cluster (string): the name of a cluster to scrape (defaults to scraping all clusters)
* -config.scrape-interval (duration): interval at which to scrape
  the AWS API for ECS service discovery information (default 1m0s)
* -config.scrape-times (int): how many times to scrape before
  exiting (0 = infinite)
* -config.write-to (string): path of file to write ECS service
  discovery information to (default "ecs_file_sd.yml")
* -config.role-arn (string): ARN of the role to assume when scraping
  the AWS API (optional)
* -config.server-name-label (string): Docker label to define the server name
  (default "PROMETHEUS_EXPORTER_SERVER_NAME")
* -config.job-name-label (string): Docker label to define the job name
  (default "PROMETHEUS_EXPORTER_JOB_NAME")
* -config.path-label (string): Docker label to define the scrape path of the
  application (default "PROMETHEUS_EXPORTER_PATH")
* -config.filter-label (string): docker label (and optional value) to filter on "NAME_OF_LABEL[=VALUE]".
* -config.port-label (string): Docker label to define the scrape port of the application
  (if missing an application won't be scraped) (default "PROMETHEUS_EXPORTER_PORT")

## Usage

First, build this program using the usual `go get` mechanism.

Then, run it as follows:

* Ensure the program can write to a directory readable by
  your Prometheus master instance(s).
* Export the usual `AWS_REGION`, `AWS_ACCESS_KEY_ID` and
  `AWS_SECRET_ACCESS_KEY` into the environment of the program,
  making sure that the keys have access to the EC2 / ECS APIs
  (IAM policies should include `ECS:ListClusters`,
  `ECS:ListTasks`, `ECS:DescribeTask`, `EC2:DescribeInstances`,
  `ECS:DescribeContainerInstances`, `ECS:DescribeTasks`,
  `ECS:DescribeTaskDefinition`, `ECS:DescribeClusters`). If the program needs to assume
  a different role to obtain access, this role's ARN may be
  passed in via the `--config.role-arn` option. This option also
  allows for cross-account access, depending on which account
  the role is defined in.
* Start the program, using the command line option
  `-config.write-to` to point the program to the specific
  folder that your Prometheus master can read from.
* Add a `file_sd_config` to your Prometheus master:

```
scrape_configs:
- job_name: ecs
  file_sd_configs:
    - files:
      - /path/to/ecs_file_sd.yml
      refresh_interval: 10m
  # Drop unwanted labels using the labeldrop action
  metric_relabel_configs:
    - regex: task_arn
      action: labeldrop
```

To scrape the containers add following docker labels to them:

* `PROMETHEUS_EXPORTER_PORT` specify the container port where prometheus scrapes (mandatory)
* `PROMETHEUS_EXPORTER_SERVER_NAME` specify the hostname here, per default ip is used (optional)
* `PROMETHEUS_EXPORTER_JOB_NAME` specify job name here (optional)
* `PROMETHEUS_EXPORTER_PATH` specify alternative scrape path here (optional)
* `PROMETHEUS_EXPORTER_SCHEME` specify an alternative scheme here, default is http (optional)

By docker labels one means `dockerLabels` map in ECS task definition JSONs like that:
```json
{
  ...
  "containerDefinitions": [
    {
      ...
      "dockerLabels": {
        "PROMETHEUS_EXPORTER_PORT": "5000"
      }
    }
  ]
  ...
}
```

That's it.  You should begin seeing the program scraping the
AWS APIs and writing the discovery file (by default it does
that every minute, and by default Prometheus will reload the
file the minute it is written).  After reloading your Prometheus
master configuration, this program will begin informing via
the discovery file of new targets that Prometheus must scrape.

