# Mech
An open container orchestration framework.

## Goals
Most container orchestration services rely heavily on convention, and can be cumbersome to adapt or customize for different use cases.
Mech intends to provide a solid foundation for users who wish to build or customize their own container orchestration. 

#### Mech should 
 - Provide users with basic guarantees regarding safety and error handling
 - Allow maximum freedom in configuration
 - Have only minimal requirements
 - Be easy to extend
 - Be well documented and easy to use

## Architecture
Mech is designed with Service Oriented Architectures in mind. There is no central control mechanism in Mech, instead, each Service is deployed as an independant unit, capable of configuring itself whenever needed.

#### Tasks
Users define Tasks, which commonly provide a single service, and may depend on other services provided by other Tasks.
Tasks do not necessarily require custom container images, and it is recommended to provide services with official images whenever possible. This allows users to easily upgrade and update software for common services. For example, Mech can run a sharded and replicated database while only using the official database container image. Only a configuration change is required to update the entire to a new version of the database.
For instances where an official image is not flexible enough in configuration, Mech provides an example implementation of a Task image built from official images that performs additional configuration.

#### Managers
Mech introduces Managers as a mechanism for configuring and running Tasks. Managers are the most important component in Mech, and carry several responsibilities:
 - Starting and Stopping Task containers
 - Configuring Task containers
 - Gracefully recover Task failures and errors

How these responsibilities are implemented is left to the user. Mech provides a default framework for Managers, exposing hooks to the user where Task specific behaviour can be implemented. For example, when a Task is started, a Manager can broadcast the availability of a service to the rest of the cluster.

More details on these hooks and Managers in general will follow.

## History
Mech is an adaptation of the orchestration service developed by Phusion to run the Union Station production environment.

## Usage Notice
Mech is currently in development, and is not ready for use.
