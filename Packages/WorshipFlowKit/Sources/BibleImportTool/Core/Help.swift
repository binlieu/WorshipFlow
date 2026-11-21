// LIB-004b: help text. Examples never show a password.
enum Help {
    static let general = """
        wf-bible-import: move Bible translations into a WorshipFlow library.

        Usage:
          wf-bible-import inspect --mysql [options]    list the versions in a Bible database
          wf-bible-import export  --mysql [options]    write one version as a translation file
          wf-bible-import import  --library <Library.sqlite> --file <path>   load a translation file into a library

        Run `wf-bible-import <command> --help` for the options of one command.

        The tool never accepts a password as an argument. For MySQL, set MYSQL_PWD in the environment, or type it at the
        prompt. The password is passed to the mysql client through its environment and is never printed or written.

        Exit status: 0 done; 1 the work failed (one line says why); 2 the command line is wrong; 3 refused to touch the
        library (it looks in use, or the translation is already there).

        Translation files are written wherever you say. Do not put them inside the project repository (the Bibles/
        folder at its root is ignored by git for this purpose). You are responsible for having the right to use the
        text you import.
        """

    private static let mysqlOptions = """
          --mysql                 accepted for clarity; MySQL is the only database source
          --host <name>           server host (default: the client's default)
          --port <number>         server port
          --socket <path>         Unix socket
          --user <name>           database user (default: the client's default)
          --database <name>       database name (required)
          --mysql-bin <path>      the mysql client (default: `mysql` found on PATH)
          --no-password           do not prompt for a password when MYSQL_PWD is not set
          --versions-table, --verses-table, --books-table <name>
                                  table names if they differ from versions, verses, books
          --map <table.role=column>
                                  name a column by hand when it cannot be found: roles are versions.id, versions.code,
                                  versions.name, versions.language, verses.version, verses.book, verses.chapter,
                                  verses.verse, verses.text, books.order, books.name_en. May be repeated.
        """

    static let inspect = """
        Usage: wf-bible-import inspect --mysql --database <name> [options]

        Lists every version in the database with its verse, book and chapter counts. Reads only; no verse text is printed.

        Options:
        \(mysqlOptions)
          --schema                also print which tables and columns were found, and how they were read

        Example (password from the environment):
          MYSQL_PWD=... wf-bible-import inspect --mysql --host localhost --user root --database bible
        """

    static let export = """
        Usage: wf-bible-import export --mysql --database <name> --version <code> --out <file.json> --language <tag> [options]

        Writes one version as a translation file (format worshipflow.translation, version 1). Books are mapped by book_order
        to the 66-book canon. Empty verses, duplicates and gaps are reported. Nothing is assumed: a missing copyright or
        licence is written as "not stated"; a version is public domain only if you say --public-domain.

        Options:
          --version <code>        the version code as `inspect` shows it (required)
          --out <file.json>       where to write the file (required); refuses to replace a file unless --overwrite
          --overwrite             replace an existing output file
          --language <tag>        BCP 47 language, for example vi or en (required)
          --id <code>             the code the library will use (default: the version code)
          --name <text>           translation name (default: the database's name, else the code)
          --abbreviation <text>   short name shown on slides (default: the code)
          --copyright <text>      copyright statement (default: "not stated")
          --licence <text>        licence or terms (default: "not stated"); --license is the same
          --source <text>         where the text came from (default: the database and version code)
          --public-domain         record the text as public domain
          --owner-approved        record that the owner approved using this text; with --owner-approval-date <YYYY-MM-DD>
                                  and --owner-approval-note <text>
          --versification <name>  KJV, VI1925 or derived (default: chosen from the data)
        \(mysqlOptions)

        Example (password from the environment; the output goes outside the repository or into Bibles/):
          MYSQL_PWD=... wf-bible-import export --mysql --host localhost --user root --database bible \\
              --version VI1934 --id VI1925 --language vi --out ~/Bibles/VI1925.json --public-domain
        """

    static let importCommand = """
        Usage: wf-bible-import import --library <Library.sqlite> --file <path> [options]

        Loads a translation file into a church library. --file may be a .json translation file, one .usfm file, or a folder
        of .usfm files (then --id and --language are required). The import is one transaction: it either completes or leaves
        the library as it was.

        Options:
          --library <path>        the library file (required). It must already exist unless --create is given.
          --file <path>           the translation file or folder (required)
          --replace               replace a translation with the same code (default: refuse)
          --create                create the library file if it does not exist
          --force                 import even if another program (such as the app) seems to have the library open.
                                  Risky: the app will not see the new translation until it is restarted, and two programs
                                  writing the same file can lose changes. Quit the app first instead.
          --dry-run               read and check the file, print the report, change nothing
          For USFM only: --id, --name, --language, --abbreviation, --copyright, --licence, --source, --public-domain,
          --versification, --owner-approved, --owner-approval-date, --owner-approval-note (as for export)

        Examples:
          wf-bible-import import --library ~/Library/Application\\ Support/WorshipFlow/Library.sqlite --file ~/Bibles/VI1925.json
          wf-bible-import import --library ./Library.sqlite --file ./web-usfm --id web --language en --name "World English Bible"
        """
}
