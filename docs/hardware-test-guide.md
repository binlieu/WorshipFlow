# WORSHIPFLOW hardware test: guide for the tester

You will run a short test of your Blackmagic DeckLink card with WORSHIPFLOW, then send back one file. You do not need to understand the results. It takes about 3 minutes for the quick test.

## What you need

1. A Mac with the DeckLink card connected (for a Duo 2: through its Thunderbolt enclosure, switched on).
2. **Blackmagic Desktop Video** installed. Get it from Blackmagic's support site (search for "Blackmagic Desktop Video download"), install it, then restart the Mac.
3. Optional, for fuller results: **two short BNC cables**. With one cable you still get the basic loopback test. With none you still get the other steps.
4. The WORSHIPFLOW app you were sent.

## Open the app

1. Unzip the file you were sent and drag WORSHIPFLOW into your Applications folder.
2. If macOS says the app "is from an unidentified developer" or "cannot be opened": do not click Move to Trash. Control-click (or right-click) the app, choose **Open**, then click **Open** again. If there is no Open button, open **System Settings, Privacy & Security**, scroll down, click **Open Anyway** next to WORSHIPFLOW, and confirm.
3. In the menu bar choose **Help, then Hardware Test…**. (If you were told to, you can also start the app with the Hardware Test already open.)

## Connect the cables (only if you have them)

The card has four round BNC sockets, marked SDI 1 to SDI 4. Join them like this:

- Cable A: SDI 1 to SDI 3
- Cable B: SDI 2 to SDI 4

Push each end in until it clicks. The app tells you when to connect them, so you can leave them unplugged until asked.

## Run the test

1. In the Hardware Test window, check the card status near the top. It says one of three things:
   - **Blackmagic Desktop Video is not installed on this Mac.** Install it (see "What you need"), restart the Mac, open WORSHIPFLOW again and press **Rescan**. If it says the driver's files are on the Mac but WORSHIPFLOW could not load them, restart the Mac and try again, and tell us.
   - **Desktop Video is installed, but no DeckLink card was found.** Check the Thunderbolt cable and that the enclosure is switched on, then press **Rescan**.
   - **Card found**, with its name. Go on.

   You can still go on without a card: a report that says no card was found is useful too. Its first line will say so.
2. Leave **Quick (about 3 minutes)** chosen. Only pick Long if you were asked to.
3. Close any screens that WORSHIPFLOW has open (the app will tell you if it needs this).
4. Press the big button (**Start the test**, or **Create a report anyway** if there is no card).
5. Follow the questions on the screen. If you do not have a cable, or are not sure, press **Skip**. Leave everything else alone until the test says it is finished.
   - In the fill and key step the app may ask **"Change the card's profile?"**. A DeckLink Duo 2 sends fill and key only in one of its profiles, and changing the profile can interrupt every output on the card for a few seconds. Press **Change the profile** to let it, or **Skip** to leave the card as it is (the step is then skipped). The app never changes a profile without asking.
6. When it is finished, press **Save report…**. The file name is already filled in and the Desktop is chosen. Press Save.

## Send the file back

Send the saved file (its name ends in `WORSHIPFLOW-hardware-test.zip`) by email or any file-sharing app. Do not open or change it. It contains no names or passwords: only what the Mac and the card reported.

If a file has `SIMULATED` in its name, it came from the demonstration button, not your card. Please run the real test instead.

The first line of the report (the file `summary.txt` inside the zip) says what was tested: `REAL DEVICE TESTED: <card name>`, `NO REAL DEVICE WAS TESTED` (no card was found), or `SIMULATED RUN`. Only the first of these says anything about a real card, and even then it describes what was measured on that one run, not a certification.

## For the developer: what the report compares

The fill and key step reads the route the device reports (which SDI connector carries the fill and which the key), measures which one carries what on the loopback cables, and compares both with the manual's table (the DeckLink Duo 2 only). It states plainly which of the three agree. On a DeckLink the "reported" route is itself read from the manual's table by the bridge, so the measurement is the only independent answer. The environment step records the driver state, the driver API version, whether the framework could be loaded (the entitlement check) and the reported route of each connector pair; `summary.txt` repeats these under "THE DRIVER AND THE CARD".
