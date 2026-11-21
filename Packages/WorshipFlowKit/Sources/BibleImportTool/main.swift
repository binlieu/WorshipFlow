// LIB-004b: wf-bible-import. The work is in Core/, which the tests compile too.
import Foundation

exit(await ImportToolCLI.run(Array(CommandLine.arguments.dropFirst()), environment: .live()))
