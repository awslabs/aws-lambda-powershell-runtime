# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# This is a simple script handler for testing PowerShell failures in the PowerShell Lambda Runtime

param ($LambdaInput, $LambdaContext)

$ErrorActionPreference = 'Stop'
Invoke-NonExistentFunction
