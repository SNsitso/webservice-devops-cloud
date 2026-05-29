# Kubernetes WordPress + MySQL helm chart



# Dependencies

* **kubectl** ([installation guide is here](https://kubernetes.io/docs/tasks/tools/install-kubectl/))
* **helm** ([installation guide is here](https://helm.sh/docs/intro/install/))



***kubectl** will be automatically configured to your created cluster*

You can check your demo-cluster status with next command
```sh
kubectl get nodes
```

# Usage

1) Clone this git repository
```sh
git clone https://github.com/DataScientest/helm-wordpress.git
```
2) Execute next commands **from repository directory**

*check that all templates are valid*
```sh
cd helm-wordpress
helm template .
```
*install chart*
```sh
helm install wordpress-mysql . --values=values.yaml
```
3) Check your WordPress service **NodePort**  with next command (may take some time)
```sh
kubectl get service -n wordpress
```
*By-default namespace that used in the chart called **wordpress**. If you changed it, make sure you define the proper namespace in **kubectl get** command.*

Now you can check this IP address with web-browser

# Helm Variables
Defined in [values.yaml]([https://github.com/ltblueberry/wordpress-mysql-helm-chart/](https://github.com/DataScientest/helm-wordpress)blob/main/values.yaml)

| Name              | Default Value       |Difinition   |
|-----------------------|---------------------|---------------------|
| `namespace` | `wordpress` |Kubernetes namespace|

## `wordpress`:
| Name              | Default Value       |Difinition   |
|-----------------------|---------------------|---------------------|
| `deployment.image` | `wordpress:4.8-apache` |Docker image for Wordpress|
|`deployment.replicaCount` | `1` |Number of Pods to run
|`service.type` |` NodePort` |Kubernetes Service type
|`service.port` | `80 `|Publishing port

## `mysql`:
| Name              | Default Value       |Difinition   |
|-----------------------|---------------------|---------------------|
| `deployment.image` | `mysql:5.6` |Docker image for MySQL|
|`deployment.replicaCount` | `1` |Number of Pods to run
|`service.type` |` ClusterIP` |Kubernetes Service type
|`service.port` | `3306 `|Publishing port
|`pvc.accessMode` | `ReadWriteOnce `|PVC Access mode
|`pvc.storage` | `2Gi `|PVC Storage size

# Uninstall
1) Execute the next command to get the list of helm releases
```sh
helm list
```
2) Execute the next command to uninstall helm release by RELEASE_NAME
```sh
helm uninstall wordpress-mysql
```

## License

**[MIT License](LICENSE)**

Copyright (c) 2023 Datascientest
