# kube-keytab-secret-generator

A Kubernetes job for generating Kerberos keytabs as secrets.  Kerberos keytabs are used by many different software packages to allow for authentication to Windows Active Directory on Linux.  This job can also be reused to update or create a new secret when the password changes for the account/principal.

By using a Kubernetes job the Kerberos keytab can be created for use in Kubernetes without the need for having the Kerberos utlilities installed locally (i.e. Windows PC) and allows for the safe creation of keytab without being stored in application repos or source code.

## Getting Started

These instructions will cover the usage and deployment of a [Kubernetes Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) that allows for the creation of a [Kubernetes Secret](https://kubernetes.io/docs/concepts/configuration/secret/) that holds a Kerberos keytab.

This job will run a precreated container which will be pulled from Docker Hub.  All that is included as part of the container is minmum Ubuntu/Kubernetes/Kerberos packages required to run and a bash script that does the work of creating the secret on Kubernetes.

What is included in the container is visable by reviewing the [dockerfile](dockerfile) and [generate-keytab-secret.sh](scripts/generate-keytab-secret.sh) script.

### Prerequisities

Previous experiance with Kerberos and Kubernetes is required to understand how to effectively use this Job.  Also the ability to create deployments and secrets on a Kubernetes cluster.

The account/princpal should be created/updated prior to creating the keytab secret.  This is because a Key Version Number (KVNO) is required as part of creating and using the keytab.  When a password for the account/princpal the KVNO should increment as well.

If Service Principal Names (SPNs) will be used as part of the deployment they should be created prior to creating the keytab as well.

### Usage

For the job to work multiple components are required.

1. Kubernetes Service Account with RBACs - The service account will need access to list, create and delete secrets in the namespaces where the job will be used.

2. Kubernetes Secret with Account Password - While the password is passed as an environment variable into the container, it should not be done as cleartext in the deployment.  An init container could also be used to pull the value of the password from something like Hashcorp Vault or some othe external secret store as well.

#### Kubernetes Service Account

A sample of the service account and RBACs is included in this repo.  To allow for this job to create secrets on all namespaces a cluster role was used.  The access granted should be the least required to run the job and create/replace the secret.  Access has not be granted to read secrets on the cluster.  But delete is granted to allow for the replacement of a current secret with a new keytab.

[yaml/service-account.yaml](yaml/service-account.yaml)

Update sample with your namespace name.

#### Kubernetes Secret with Account Password

The delivery of password for use by the job can be done by creating a Kubernetes secret.

```shell
kubectl create secret generic keytab-password --from-literal=password={{password}} -n {{namespace}}
```

#### Kubernetes Job Deployment

A sample deployment yaml is included in this repo for deploying the job.  It can be updated based on the required parameters for your account/principal and environment.  The parameters for creating the keytab are driven based on the environment variables passed in the job deployment.

[yaml/deploy-job.yaml](yaml/deploy-job.yaml)

```shell
kubectl apply -f ./deploy-job.yaml -n {{namespace}}
```

##### Kubernetes Job Environment Variables

* `PASSWORD` - Required - Password for Kerberos account/principal 
* `ACCOUNT` - Required - Kerberos account/principal name
* `ENCRYPTION_METHODS` - Required - Kerberos [encryption types](https://web.mit.edu/kerberos/www/krb5-latest/doc/admin/conf_files/kdc_conf.html#encryption-types) (can be comma delimited to allow for mulitple)
* `REALM` - Required - Kerberos realm name (must be uppercase)
* `SECRET_NAME` - Required - Name of Kubernetes secret to be created for keytab
* `KVNO` - Optional - Kerberos [key version number](https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-kile/31411d28-7ad5-4237-a1f9-50738a08aa82) (will default to 2)
* `SPNS` - Optional - Kerberos SPNs attached to account (can be comma delimited to allow for mulitple)
* `SECRET_NAMESPACE` - Optional - Name of Kubernetes namespace where the secret will be created (defaults to namespace where service account is created)
* `SECRET_VALUE` - Optional - Key name in Kebernetes secret (defaults to keytab)

#### Kubernetes Job Clean-up

Once the job has seccessfully run and the keytab has been validated, the job can be removed off the cluster.

```shell
kubectl delete -f ./deploy-job.yaml -n {{namespace}}
```

### Troubleshooting

1. Validate job has run after deployment by describing job.

```shell
kubectl describe job kube-keytab-secret-generator -n {{namespace}}
```

2. Get logs from job pod to review if all steps were completed.  Get pod name by using selector.

```shell
kubectl get pods --selector=app=kube-keytab-secret-generator -n {{namespace}}
```

Then get the logs from the pod.

```shell
kubectl logs {{pod-name}} -n {{namespace}}
```

All errors should be visable as part of the log output.  The following as a sample output based on a successful run.

```
Defaulting to secret value of keytab
Defaulting KNVO to the value of 2 assuming password has not changed
User "sa-keytab" set.
Context "sa-context" created.
Kubernetes secret sqlmi-test-1-keytab-secret exists will update value keytab
Using ktutil for keytab generation...
spawn /usr/bin/ktutil
ktutil:  addent -password -p sqlmi-test-1@DROCX.LOCAL -k 2 -e aes256-cts-hmac-sha1-96
Password for sqlmi-test-1@DROCX.LOCAL: 
ktutil:  wkt tmp.keytab
ktutil:  spawn /usr/bin/ktutil
ktutil:  addent -password -p MSSQLSvc/sqlmi-test-1.azure.drocx.local@DROCX.LOCAL -k 2 -e aes256-cts-hmac-sha1-96
Password for MSSQLSvc/sqlmi-test-1.azure.drocx.local@DROCX.LOCAL: 
ktutil:  wkt tmp.keytab
ktutil:  spawn /usr/bin/ktutil
ktutil:  addent -password -p MSSQLSvc/sqlmi-test-1.azure.drocx.local:1433@DROCX.LOCAL -k 2 -e aes256-cts-hmac-sha1-96
Password for MSSQLSvc/sqlmi-test-1.azure.drocx.local:1433@DROCX.LOCAL: 
ktutil:  wkt tmp.keytab
ktutil:  spawn /usr/bin/ktutil
ktutil:  addent -password -p sqlmi-test-1@DROCX.LOCAL -k 2 -e arcfour-hmac
Password for sqlmi-test-1@DROCX.LOCAL: 
ktutil:  wkt tmp.keytab
ktutil:  spawn /usr/bin/ktutil
ktutil:  addent -password -p MSSQLSvc/sqlmi-test-1.azure.drocx.local@DROCX.LOCAL -k 2 -e arcfour-hmac
Password for MSSQLSvc/sqlmi-test-1.azure.drocx.local@DROCX.LOCAL: 
ktutil:  wkt tmp.keytab
ktutil:  spawn /usr/bin/ktutil
ktutil:  addent -password -p MSSQLSvc/sqlmi-test-1.azure.drocx.local:1433@DROCX.LOCAL -k 2 -e arcfour-hmac
Password for MSSQLSvc/sqlmi-test-1.azure.drocx.local:1433@DROCX.LOCAL: 
ktutil:  wkt tmp.keytab
ktutil:  Deleting current secret sqlmi-test-1-keytab-secret and replacing
secret "sqlmi-test-1-keytab-secret" deleted
secret/sqlmi-test-1-keytab-secret created

Keytab secret script complete
```

## Find Us

* [GitHub](https://github.com/djr747/kube-keytab-secret-generator)
* [Docker Hub](https://hub.docker.com/repository/docker/djrsystems/kube-keytab-secret-generator)

## Contributing

Feel free to create issues or pull requests.

## Versioning

Currently no versioning is being used and the latest Ubuntu 20.04 and Kubenetes CLI will be used on .  All updates will be reflected in the latest push to Docker Hub.  At somepoint a nightly rebuild job maybe used to captured the latest updates for the Ubuntu 20.04 base image.

## Authors

* **Derek Robson** - *Initial work* - [DJR747](https://github.com/djr747)

See also the list of [contributors](https://github.com/djr747/kube-keytab-secret-generator/contributors) who 
participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Testing

All testing has been completed manually without full regrestion testing.  The keytabs generated have been used with [Azure ARC Data Services SQL Managed Instance](https://docs.microsoft.com/en-us/azure/azure-arc/data/deploy-active-directory-sql-managed-instance) as part of testing.
