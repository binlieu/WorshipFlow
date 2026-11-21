// LIB-004b: command-line parsing. A password is never accepted, in any spelling, and never echoed back.
import Testing
import Foundation
@testable import ScriptureStore

@Suite struct ToolArgumentTests {
    private let spec = OptionSpec(values: ["host", "database", "map"], flags: ["mysql", "schema"])

    @Test func valuesFlagsAndInlineForms() throws {
        let p = try ArgumentParser.parse(["--mysql", "--host", "h", "--database=db", "--map", "a=b", "--map=c=d", "extra"], spec: spec)
        #expect(p.has("mysql") && !p.has("schema"))
        #expect(p.value("host") == "h" && p.value("database") == "db" && p.all("map") == ["a=b", "c=d"] && p.positional == ["extra"])
        #expect(try ArgumentParser.parse(["--help"], spec: spec).has("help"))
        #expect(try ArgumentParser.parse(["-h"], spec: spec).has("help"))
    }

    @Test func mistakesGetOneLine() {
        for (args, fragment) in [(["--nope"], "unknown option --nope"), (["--host"], "--host needs a value"), (["--mysql=1"], "does not take a value"), (["-x"], "unknown option")] {
            do { _ = try ArgumentParser.parse(args, spec: spec); Issue.record("expected an error for \(args)") }
            catch let error as UsageError { #expect(error.message.contains(fragment), "\(args): \(error.message)") } catch { Issue.record("wrong error") }
        }
    }

    @Test(arguments: [["--password", "hunter2"], ["--password=hunter2"], ["--passwd=hunter2"], ["--pass", "hunter2"], ["--pwd=hunter2"],
                      ["-phunter2"], ["-p", "hunter2"], ["--mysql-pwd=hunter2"], ["--db-password", "hunter2"]])
    func passwordsOnTheCommandLineAreRefusedAndNeverEchoed(_ args: [String]) {
        do { _ = try ArgumentParser.parse(args, spec: spec); Issue.record("expected a refusal") }
        catch let error as UsageError {
            #expect(error.message == ArgumentParser.passwordRefusal)
            #expect(!error.message.contains("hunter2") && error.message.contains("MYSQL_PWD"))
        } catch { Issue.record("wrong error") }
    }
}
