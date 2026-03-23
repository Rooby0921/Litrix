[English](./README.md) | [简体中文](./README.zh-CN.md)

# Litrix
Litrix is derived from the words literature and matrix. It is designed to manage local papers in a matrix-like way. The design of Litrix draws inspiration from Zotero, Lattice, and the Tahoe-style Finder window, so in a sense it is a blend of several design languages.
Litrix is shared for learning and communication only, and I promise it will never become paid software.

![Main Window](docs/images/main_window.png)

![Icon Page](<docs/images/icon page.png>)

# Why Litrix
Whether it is Zotero or Lattice, both are trying to present literature summaries elegantly, but they do not really reach deeper layers of a paper, such as research methods, research questions, conclusions, limitations, or figure design. In other words, one is trying to be powerful and the other is trying to be beautiful, but neither is mainly focused on helping users stay inside a reading workflow long enough to deepen understanding and gain more from reading. If you want to understand a paper quickly and more deeply, the usual process is often this: first find the paper, maybe not easily; then open it, maybe with lag; then search through it for the key details you no longer remember, especially in English. By the time you find them, a lot of time has already passed.
Even in the latest version of Lattice, it is still hard to immediately find a paper's research questions, limitations, figure design, or, most importantly, your own earlier thoughts about it. Long before Lattice was released, some of my classmates were already trying other approaches. There were two typical ones. One was to organize papers in Zotero and then build a separate literature document that grouped other people's viewpoints together, with personal comments added on top. The second was to reorganize papers in Excel, while Zotero became just an optional tool for collection and reading. Students who preferred that route often felt that reading directly on the web was more convenient and less costly in time and memory. I do not think there is one workflow that should be treated as the correct answer for everyone. Each person's habits, discipline background, and way of thinking lead them to a different working style. But I do think it is worth exploring a literature workflow that is, at least in theory, more convenient for deep reading and note-taking, so that more people can stay immersed in reading while also reaching the deeper layers of a paper more quickly.
After thinking about these limits, I carefully looked through GitHub's open-source rules and decided to redesign a literature reading tool with Zotero and Lattice as references. That tool became Litrix. Litrix does learn from both of them, but it is fundamentally different in code, feature design, and product philosophy. In interface design, Litrix resembles the non-commercial beta version of Lattice in parts of the left sidebar, but Lattice itself also resembles Finder in some ways. If users later feel that Litrix looks too much like a copy of Lattice or like a different version of the same product, I will keep pushing Litrix toward a more independent visual identity.

*A combination of literature and matrix.*

I did a small informal survey among classmates (*n* = 10) and found that more of them preferred making literature notes in Excel. They felt Excel could quickly present the key information of a paper, such as research questions, methods, sample size, and innovations, while also giving them space for their own notes: what inspired them, what was worth taking away, and what deserved criticism. I eventually asked why they still used tables when Zotero could theoretically do some of this as well. A few typical answers were: "Zotero cannot customize columns," "Zotero only gives me one row, it cannot show that much content," "Zotero cannot hold images," "When I want to view content in Zotero, I have to click into a secondary menu just to see my own notes," "Zotero is too laggy," and "Zotero is not pretty." I am only showing the voices of the dissenters here, but everyone knows Zotero is still an undeniably powerful literature manager.
So if Excel is that convenient, why not just use Excel directly?
Excel does have many advantages, but the workload is huge. If someone wants to extract a paper's research questions, methodology, data analysis methods, experimental design, and other details, they still have to copy from the original paper and rewrite things by hand. In conversation, I found that this does not necessarily consume too much time when deep reading is involved, but the low-level repetitive work still feels tedious.

*The tide of the times washes over every grain of sand.*

Educational technology is an awkward discipline. On the optimistic side, people say educational technology understands education better than computer science, and technology better than education studies. On the pessimistic side, people say educational technology understands neither computing nor education. The second view is not completely groundless, and it is not always the students' fault. Some universities classify educational technology under science, but in practice it is neither computer science nor education studies, which means students often cannot easily enter either type of job market. My own view of the real-world value of educational technology is closer to the pessimistic side, but I also think that what exists has its reasons. Academic background is often a door-opener, but there are always exceptions, just as rules are always broken eventually. The optimistic side is sometimes simply too optimistic. There are many reasons for this, and Teacher Saibo Yangdi has offered a thoughtful [analysis](https://www.xiaohongshu.com/discovery/item/694f3458000000002103eede?source=webshare&xhsshare=pc_web&xsec_token=ABCfxTaZd1R9qsjwo6jD8L9KXFMxjSL3IEyrBFotewak4=&xsec_source=pc_share) through many cases.
I mention educational technology here because this awkward discipline has shown surprising vitality in the age of AI. Every new wave of technology seems to breathe fresh life into it, and I am one of those educational technology students.
When I first tried using Codex for programming, I was deeply impressed by its agent capabilities. That also gave me a new feeling. People online often joke that "He Tongxue" was the biggest beneficiary of 5G. From the perspective of an educational technology student, educational technology may also become one of AI's biggest beneficiaries. In my view, He Tongxue's success was not caused by 5G itself, but by his precise sense of how to capture and shape a technological moment. People may say he does not really understand the technology, but his success on Bilibili is undeniable.
So I cautiously read through the open-source manuals and tried to design a literature tool built around the idea of constructing a matrix.

*Epilogue*

Thank you for reading this far. All of this could have been compressed into one neat sentence, just as we often do when writing in a foreign language. But in an era flooded with AI text, human long-windedness sometimes feels like proof that I am still a person. I wish you good health, safety, and peace. Those things are the most basic ones, and also the easiest to overlook.

## Key Design

### A Direct and Dense Literature Matrix

Litrix changes the cramped single-line presentation common in traditional literature managers. With expanded rows (shortcut `Command + =`), users can inspect a paper's deeper information directly in one interface. Combined with large image preview through the Space key, complex experimental figures, flow charts, and other visual materials no longer hide inside secondary menus. The experience feels as efficient as working in Excel, yet more visual and easier to read than Excel. You can also hover over an image in the matrix and press Space to enlarge it. For many Excel users, this is almost a dream feature.

![Feature Preview](docs/images/feature_preview1-1.png)

![Feature Preview](docs/images/feature_preview1-2.png)

![Feature Preview](docs/images/feature_preview1-3.png)

### An AI-Driven Automation Workflow

Unlike older tools where literature entries only support plain text, Litrix emphasizes the importance of images in literature reading. Key notes you produce while reading, important figures from the paper, and critical details in data analysis can all be captured and pasted into metadata very quickly. In addition, users can create or open a text note with `Command + N`.

![Feature Preview](docs/images/feature_preview2-1.png)

![Feature Preview](docs/images/feature_preview2-2.png)

### A Highly Open Matrix You Can Shape Yourself

Litrix supports custom metadata extraction prompts. Users can obtain API access for free from platforms such as SiliconFlow or Alibaba Cloud DashScope. This design allows AI to take a deeper role in the literature workflow by automatically extracting, classifying, and summarizing the small but important details that would otherwise require tedious manual entry, so that more attention can stay with high-value thinking and writing. In the future, Litrix plans to add more Excel-like behavior, including custom column titles. If you feel there are too many metadata types right now, you can turn some of them off from `Litrix > Settings > Column`.

![Feature Preview](docs/images/feature_preview3-1.png)

![Feature Preview](docs/images/feature_preview3-2.png)

### Fast and Precise Search and Citation

In Litrix, after selecting a paper, `Command + C` copies the in-text citation, and `Command + Shift + C` copies the reference-list entry. `Command + F` opens quick search, and `Command + Shift + F` enters advanced search. This makes it much faster to insert citations and locate papers while writing, taking notes, or organizing material. Litrix also provides search, advanced search, collections, tags, and recent reading, so it is easier to find exactly the paper you want.

![Feature Preview](docs/images/feature_preview4-0.png)

![Feature Preview](docs/images/feature_preview4-1.png)

![Feature Preview](docs/images/feature_preview4-2.png)

## What Litrix Is For

- Build a literature matrix in an Excel-like way
- Use AI to create original paper metadata automatically
- Use collections, tags, ratings, and notes to review papers quickly
- Find papers quickly through several search methods
- Expanded row views that Zotero never had
- Recent Reading, which only arrived in Zotero 9
- Export BibTeX, detailed Markdown, and attachments
- Manual citation that can feel even faster than automatic citation
- A visually appealing interface inspired by Lattice, an exceptionally refined literature manager: https://github.com/stringer07/Lattice_release/releases

## Requirements

- macOS 14 or later
- Xcode 26.3+ or Swift 6.2+
- If you want AI metadata enrichment, fill in an API key in the app settings

This repository has been checked locally with `Swift 6.2.4` and `Xcode 26.3`.

## Keyboard Shortcuts

Keyboard shortcuts are one of the core features of Litrix.

### Main Window

| Shortcut | Action |
| --- | --- |
| `⌘N` | Create a new plain-text note for the selected paper |
| `⌘F` | Focus the search field; press `⌘F` again or `Esc` to exit search |
| `⌘⇧F` | Open Advanced Search |
| `Space` | Quick Look preview for the selected PDF; if hovering over an image thumbnail, preview the image instead |
| `Return` / `Enter` | Open the selected paper's PDF |
| `↑` | Select the previous paper |
| `↓` | Select the next paper |
| `⌘Delete` | Delete the selected paper |
| `⌘A` | Select all visible papers in the current list |
| `⌘[` | Toggle the left sidebar |
| `⌘]` | Toggle the right metadata inspector |
| `⌘-` | Switch to compact row height |
| `⌘=` / `⌘+` | Switch to expanded row height |

### Citation Copying

| Shortcut | Action |
| --- | --- |
| `⌘C` | Copy in-text citation for the selected paper, for example `(Du & Wang, 2025)` |
| `⌘⇧C` | Copy reference citation for the selected paper |

### Quick Tags

| Shortcut | Action |
| --- | --- |
| `1` to `9` | Apply the corresponding quick tag to the selected paper(s) |

Note: Quick tag numbers must be assigned in Settings first. Batch application is supported for multi-selection.

### Sidebar

| Shortcut | Action |
| --- | --- |
| `Return` / `Enter` | Rename the selected collection or tag inline |

### Advanced Search

| Shortcut | Action |
| --- | --- |
| `Return` | Run search |
| `Esc` | Close the Advanced Search window |

### Note Window

| Shortcut | Action |
| --- | --- |
| `⌘W` | Close the note window |
| `⌘N` | Create a new plain-text note for the selected paper |

### Dialogs and Forms

| Shortcut | Action |
| --- | --- |
| `Return` | Confirm DOI import |
| `Return` | Save a new collection or tag |
| `Return` | Confirm adding a custom item |

### Settings

| Shortcut | Action |
| --- | --- |
| `⌘S` | Save the Metadata Prompt draft |

## Screenshots

![Main Window](docs/images/main_window.png)
Main window

![Metadata Panel](docs/images/metadata-panel.png)
Metadata panel content. You can change the extracted fields and formatting by editing the prompt at `Litrix > Settings > API > Metadata Prompt`.

## Release Contents

- `Litrix-0.9-beta1.dmg`: installer package
- `API配置教程[中文].pdf`: API configuration guide in Chinese
- `docs/images/`: screenshot assets used in this repository

## Known Issues

Because the author has limited time, some known but low-risk issues are not fixed yet and will be improved in later versions. If you find a new bug, feedback is very welcome at `robby260314@gmail.com`.

1. Toolbar layout cannot be saved.
2. The right inspector animation is not smooth enough.
3. Some interface prompts are still in Chinese even though the target language is English.
4. No dark mode yet.
5. No language switcher yet.
6. Advanced search cannot yet lock onto custom collections.

## Feedback

You are welcome to submit feedback, bug reports, and feature requests through GitHub Issues. If you run into problems, please try to include your macOS version, the steps you took, the expected result, the actual result, and any relevant screenshots or sample files. If you have feature ideas, sharing your usage scenario and the background behind your needs will help me judge the design direction more clearly. Litrix is still evolving, and feedback, testing, and suggestions from real use cases are genuinely helpful. To avoid rights disputes, Litrix does not open the original source code, but Litrix promises to remain free forever.

## Disclaimer

This project was developed with assistance from OpenAI Codex (about 60% vibe coding, though honestly it could have been 100%). The author is not formally trained in computer science, but self-taught. The project has been reviewed manually in an effort to avoid unauthorized code reuse, plagiarism, or other intellectual property issues. However, because AI-assisted development is not fully predictable, if any individual or organization believes that this project involves infringement, improper reuse, or another related dispute, please contact the author through the public repository or by email (`robby260314@gmail.com`). The author will actively cooperate in review and revision after verification.

This project references Lattice, Zotero, Finder, and similar resource-management tools in its interface organization and interaction patterns. Such reference is mainly limited to the level of visual design and does not involve direct copying of source code, icons, screenshots, written copy, or other resource files. According to general principles of copyright law, copyright usually protects the protected expression in software and does not automatically extend to abstract ideas, program logic, systems, methods, or layouts by themselves. If any rights holder believes that a specific expression in this project is still inappropriate, they are welcome to contact the author. The author will handle the matter with respect and caution.

This project is published only for public communication, learning, research, and personal use. The author has not sold this program, authorized paid distribution, or required payment through any channel. If any third party distributes this program through forced payment, bundled charges, or other improper charging methods without the author's authorization, that behavior is unrelated to the author and does not represent the author's position. Please judge distribution channels carefully. Reporting email: `robby260314@gmail.com`

## Ethical Disclosure

This project used AI coding assistance during development to improve prototyping efficiency. The author has always treated human review, human revision, and human judgment as necessary steps before release, and has tried to avoid directly adopting material with unclear origin, unclear authorization, or possible intellectual property risk.

## Acknowledgements

Heartfelt thanks to Zotero and Lattice for their outstanding exploration and contribution in the field of literature management software. Their products provided important inspiration for the interface design of this literature tool. Zotero is a powerful literature manager loved by a large user base. Lattice, after Zotero, is an exceptionally refined literature manager and has received broad praise from users. A related introduction can be found at [Lattice_release](https://github.com/stringer07/Lattice_release/blob/master/README.zh-CN.md). In addition, thanks to OpenAI Codex for providing support during the development of this project and helping the author complete the prototype without a computer science background (Codex asked me to write this sentence).
