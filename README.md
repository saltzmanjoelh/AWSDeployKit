## AWSDeployCore
Helps with building Swift packages in Linux and updating an existing AWS Lambda. 

The `AWSDeploy` product is simply an executable target for the `AppDeployer`. If you plan on [using this from the command line](#using-from-the-command-line), you will simply build the aws-deploy target and copy the product somewhere. However, I prefer to [use this in Xcode](#use-this-in-xcode).

## How does it work?

### Pick a path
In it's simpliest form, you execute the `aws-deploy` binary and it will use your current working directory. You can override this and specify which directory with `-d path-to-package` or `--directoryPath path-to-package`. 

### Build in Docker
It will read your Swift package and from within Docker and build all of the executable targets. You can override this in a couple different ways. Since it will build all executables by default, you can simply provide `-s name-of,targets,to-skip`. Or you can tell it to explicity build only one target by passing the executable target's name, as in:  `aws-deploy example-lambda` .

The Docker image `swift:5.3-amazonlinux2` will be used by default. You can override this by adding a Dockerfile to the root of the package's directory. 

The built products will be available at `./build/lambda/$EXECUTABLE/`. You will also find a zip in there which contains everything that can be uploaded to the AWS Lambda. The archive will be in the format `$EXECUTABLE_yyyymmdd_HHMM.zip`, where the date is the date when the build occurred.

### Blue/green publish changes
If you pass the `-p` or `--publishBlueGreen` flag, it will publish the changes to a Lambda function. By default, we assume that the Lambda function name matches the executable's name which will also be the prefix of the archive's filename `$EXECUTABLE_yyyymmdd_HHMM.zip`. So, you have an executable target in your Swift package called `example-lambda`, the archive will be named `example-lambda_yyyymmdd_HHMM.zip` and the matching Lamba should be named `example-lambda`. We assume that the Lambda has already been setup. This will simply handle the updates.

The blue/green deployment steps are as follows:
* Update the Lambda function code. [UpdateFunctionCode](https://docs.aws.amazon.com/lambda/latest/dg/API_UpdateFunctionCode.html)
* Publish the updated code to $LATEST so that a new version number is created. [PublishVersion](https://docs.aws.amazon.com/lambda/latest/dg/API_PublishVersion.html)
* Verify that the function does not have startup errors. [Invoke](https://docs.aws.amazon.com/lambda/latest/dg/API_Invoke.html)
* Point the Lambda's `production` alias to the new version. [UpdateAlias](https://docs.aws.amazon.com/lambda/latest/dg/API_UpdateAlias.html)

## Using in Xcode
You are basically duplicating the `aws-deploy` target.

* Create a new executable target that depends on `AWSDeployCore`
* You only need 2 lines in the `main.swift` file:
  ```swift
  import AWSDeployCore
  AppDeployer.main()
  ```
* Switch your target in Xcode to your new target
* Press `cmd` + `shift` + `<` to edit the scheme
* Add the path to your project in the "Arguments Passed On Launch" section`-d /path/to/project/` 

Now when you want to deploy, simply pick your new target and run. Logs should appear in the Xcode console. 


## Using from the command line

* Build the `aws-deploy` target.
* Copy to `/usr/local/bin` or similar.
* Run it with the path to your project directory. `aws-deploy -d /path/to/project`.
