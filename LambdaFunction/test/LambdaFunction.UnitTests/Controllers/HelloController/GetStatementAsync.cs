using System;
using System.Linq;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Moq;
using TestStack.BDDfy;
using Xunit;

namespace LambdaFunction.UnitTests.Controllers.HelloController
{
    public class GetStatementAsync
    {
        [Fact]
        public void TestSuccess()
        {
            LambdaFunction.Controllers.HelloController helloController = null;
            Mock<ILogger<LambdaFunction.Controllers.HelloController>> logger = null;

            IActionResult result = null;

            this
            .Given(() =>
            {
                logger = new Mock<ILogger<Api.Controllers.HelloController>>();
            }, "a mocked logger")
                .And(() =>
                {
                    helloController = new LambdaFunction.Controllers.HelloController(logger.Object);
                }, "a controller using the mock")
            .When(() =>
            {
                result = helloController.Get();
            }, "a request is made to 'get'")
            .Then(() =>
            {
                result.Should().BeOfType<OkObjectResult>();
            }, "the result should be an OK object result")
            .BDDfy("HelloController.Get: Success");
        }
    }
}