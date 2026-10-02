---
name: ste-english
description: Write or rewrite text in ASD-STE100 Simplified Technical English (STE) style. Use for "simplified technical english", "STE", "ASD-STE100", "plain technical english", "explain in STE", "rewrite in STE", "check this text for STE".
license: MIT
---

# Simplified Technical English (STE) Style

STE is a controlled language for technical writing. It uses short sentences, simple verb forms, and one
meaning for each word. Its goal is text that a non-native reader understands the first time.

This skill gives STE-style output. The output is not certified. Never call it "STE-compliant". The skill
has its own short rule summary and substitution table. It does not include the ASD dictionary. For the full
rules and dictionary, read the free ASD-STE100 Issue 9 PDF at https://www.asd-ste100.org/. ASD-STE100 is a
trademark of ASD.

## When to Use This Skill

- The user asks for explanations, summaries, or plans in STE.
- The user gives text or a file and asks to rewrite it or check it against STE.
- The user wants text for a reader who is not a native English speaker.

## When NOT to Use This Skill

- Code, logs, and quoted error messages. Keep them as written.
- Legal text, licence text, and verbatim quotes.
- The user asks for a casual tone, or for marketing or narrative text.

## Two Modes

### Style mode

Write all explanations, summaries, and plans in STE until the user says stop. Put the answer first. Apply
the rules below to your own prose. Do not announce each rule you apply.

### Rewrite and audit mode

The input is text or a file. Give the output in this order:

1. The rewritten text.
2. A table with the columns `Original | Rule | Fix`. List each change that has a rule behind it.
3. One stats line: longest sentence (words), passive verbs, noun clusters of more than 3 words.

Do not edit a file unless the user asks.

## Exempt Items

Keep these exactly as written:

- Code blocks, inline code, identifiers, CLI commands, paths, URLs.
- Product names, ticket IDs, and quoted messages.

Treat these items as technical nouns. Treat computer-process verbs (commit, merge, deploy, install, click)
as technical verbs. Do not use a technical noun as a verb.

## Rules Checklist

### 1. Words

- Use one word for one meaning. Use one part of speech for each word.
- Use the same term for the same item every time. Do not change the term to avoid repetition.
- Use US spelling.

### 2. Multi-word nouns

- Use a maximum of 3 words in a noun cluster.
- Break a long cluster with a preposition or a hyphen: "report of the failed test", not "failed test report
  summary".

### 3. Verbs

- Use only the simple present, simple past, and simple future.
- Use a past participle only as an adjective: "the failed job".
- Do not use an `-ing` form as a verb. It is acceptable in a technical noun.
- Use the active voice. Use the passive in descriptive text only if the doer is unknown or not important.
- Show an action with a verb, not a noun: "inspect the file", not "do an inspection of the file".

### 4. Sentences

- Write one topic in each sentence.
- Keep the small words: articles, and "that" after verbs such as "make sure".
- Use a vertical list for complex information.
- Use connecting words such as "then", "but", and "because" between related sentences.

### 5. Procedures

- Use a maximum of **20** words in each sentence.
- Give one instruction in each sentence. Give two only if the user does them at the same time.
- Use the imperative form.
- Put the condition first: "If the build fails, read the log."
- A note gives information. It does not give an instruction.

### 6. Descriptions

- Use a maximum of **25** words in each sentence.
- Start a paragraph with the topic sentence. Keep one topic in each paragraph.
- Use a maximum of **6** sentences in each paragraph.

### 7. Safety

- Start a warning or caution with a clear command. Then give the risk.
- In an agent session, this covers destructive actions: `rm -rf`, force push, `force_result`, dropping
  data. Say what to do, then what the risk is.

### 8. Punctuation and word count

- Count a number with its unit as separate words, unless the unit is a symbol written with the number.
- Count each list item as its own sentence. Count a heading as text that needs no end punctuation.
- Count the words before a colon as part of the sentence limit.

### 9. Writing practices

- Restructure the sentence. Do not swap words one for one.
- Keep one style in the whole text.
- Do not use Latin abbreviations. Write "for example" and "that is". For "etc.", give the full list.
- Do not use `'s` for things: "the output of the job", not "the job's output".
- Use inclusive language.

## Substitution Table

This is not the dictionary. If a word is in doubt, use a simpler structure.

| Avoid | Use |
|-------|-----|
| utilize, handle (as "use") | use |
| prior to | before |
| subsequently (as "next") | then |
| ensure | make sure |
| perform, carry out | do |
| facilitate | help |
| obtain | get |
| terminate | stop |
| commence | start |
| enough | sufficient |
| modify | change |
| attempt (verb) | try |
| in the event that, in case of | if |
| however | but |
| have to | an imperative verb, or "it is necessary to" |
| should (as a requirement) | must |
| require, need | necessary ("it is necessary to ...") |
| since (as "because") | because |
| therefore | thus, as a result |
| may (as "can") | can |
| e.g. | for example |
| i.e. | that is |

## Worked Example

Before (an agent explanation of a failed CI job):

> The pipeline failed because the lint step, which was running with a stale cache, flagged numerous
> formatting violations that had been introduced in the previous commit, so it should be ensured that the
> cache is cleared prior to re-running the job.

After:

> The lint step failed. It used an old cache and found many format errors from the last commit. Clear the
> cache. Then run the job again.

Audit:

| Original | Rule | Fix |
|----------|------|-----|
| One sentence with 4 topics (46 words) | 4, 6 | Split into 4 short sentences |
| "was running" | 3 | "used" (simple past) |
| "numerous formatting violations" | 1 | "many format errors" |
| "it should be ensured" | 3, 5 | "Clear the cache." (imperative) |
| "prior to re-running" | 1, 3 | "Then run the job again." |

Stats: longest sentence 12 words, passive verbs 0, noun clusters over 3 words 0.

## Anti-Patterns

| Don't | Why |
|-------|-----|
| Replace words one for one from the table | The grammar breaks. Restructure the sentence instead. |
| Replace valid technical terms with vague words | A technical noun or verb stays exact. "Rebase" is not "move". |
| Call the output "STE-compliant" or "certified" | Only the full ASD rules and dictionary can support that claim. |
| Apply STE to code, commands, or quoted errors | The reader must see the real text. |
| Make text longer to sound formal | STE gives short, direct text. |
| Split sentences until the logic is lost | Keep connecting words so the reader sees the cause and the order. |
