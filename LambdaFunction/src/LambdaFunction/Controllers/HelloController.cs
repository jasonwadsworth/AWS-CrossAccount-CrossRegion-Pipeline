using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace LambdaFunction.Controllers
{
    [Route("hello")]
    public class HelloController : Controller
    {
        private readonly ILogger logger;

        public HelloController(ILogger<HelloController> logger)
        {
            this.logger = logger;
        }

        [HttpGet]
        public IActionResult Get()
        {
            return Ok(new { Message = "Hello, world!" });
        }
    }
}