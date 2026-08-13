"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, CardPayload, GrammarPhrase, Set, Subject } from "@/lib/api";

type Props = {
  mode: "new" | "edit";
  cardID?: string;
};

const emptyPhrase: GrammarPhrase = { text: "", note: "" };

export default function CardForm({ mode, cardID }: Props) {
  const router = useRouter();
  const [subjects, setSubjects] = useState<Subject[]>([]);
  const [sets, setSets] = useState<Set[]>([]);
  const [subjectID, setSubjectID] = useState("");
  const [setID, setSetID] = useState("");
  const [frontText, setFrontText] = useState("");
  const [answerText, setAnswerText] = useState("");
  const [phrases, setPhrases] = useState<GrammarPhrase[]>([{ ...emptyPhrase }]);
  const [newSubjectName, setNewSubjectName] = useState("");
  const [newSetName, setNewSetName] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    api
      .listSubjects()
      .then((items) => {
        setSubjects(items);
        if (mode === "new" && items.length > 0) {
          setSubjectID(items[0].id);
        }
      })
      .catch((err: Error) => setError(err.message));
  }, [mode]);

  useEffect(() => {
    if (mode !== "edit" || !cardID) {
      return;
    }
    api
      .getCard(cardID)
      .then((card) => {
        setSubjectID(card.subject_id);
        setSetID(card.set_id);
        setFrontText(card.front_text);
        setAnswerText(card.answer_text);
        setPhrases(card.grammar_phrases.length > 0 ? card.grammar_phrases : [{ ...emptyPhrase }]);
      })
      .catch((err: Error) => setError(err.message));
  }, [mode, cardID]);

  useEffect(() => {
    if (!subjectID) {
      setSets([]);
      setSetID("");
      return;
    }
    api
      .listSets(subjectID)
      .then((items) => {
        setSets(items);
        setSetID((current) => (items.some((set) => set.id === current) ? current : ""));
      })
      .catch((err: Error) => setError(err.message));
  }, [subjectID]);

  async function createSubject() {
    const name = newSubjectName.trim();
    if (!name) {
      return;
    }
    try {
      const subject = await api.createSubject(name);
      setSubjects((current) => [...current, subject].sort((a, b) => a.name.localeCompare(b.name)));
      setSubjectID(subject.id);
      setNewSubjectName("");
      setError("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create subject");
    }
  }

  async function createSet() {
    const name = newSetName.trim();
    if (!subjectID || !name) {
      return;
    }
    try {
      const set = await api.createSet(subjectID, name);
      setSets((current) => [...current, set].sort((a, b) => a.name.localeCompare(b.name)));
      setSetID(set.id);
      setNewSetName("");
      setError("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create set");
    }
  }

  function updatePhrase(index: number, key: keyof GrammarPhrase, value: string) {
    setPhrases((current) =>
      current.map((phrase, phraseIndex) =>
        phraseIndex === index ? { ...phrase, [key]: value } : phrase
      )
    );
  }

  function removePhrase(index: number) {
    setPhrases((current) => current.filter((_, phraseIndex) => phraseIndex !== index));
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError("");
    if (!subjectID) {
      setError("Select a subject before saving.");
      return;
    }
    if (!setID) {
      setError("Select a set before saving.");
      return;
    }
    if (!frontText.trim() || !answerText.trim()) {
      setError("Front and answer are required.");
      return;
    }
    setSaving(true);
    const payload: CardPayload = {
      set_id: setID,
      card_type: "speaking_expression",
      direction: "zh_to_en",
      front_text: frontText,
      answer_text: answerText,
      grammar_phrases: phrases
        .map((phrase) => ({ text: phrase.text.trim(), note: phrase.note.trim() }))
        .filter((phrase) => phrase.text || phrase.note)
    };

    try {
      if (mode === "edit" && cardID) {
        await api.updateCard(cardID, payload);
      } else {
        await api.createCard(payload);
      }
      router.push("/cards");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Save failed");
    } finally {
      setSaving(false);
    }
  }

  return (
    <section>
      <div className="pageHero">
        <div>
          <p className="eyebrow">{mode === "edit" ? "Edit set" : "Create"}</p>
          <h1>{mode === "edit" ? "Edit study set" : "Create a new study set"}</h1>
          <p className="subtle">
            Add the prompt, answer, and phrase hints that will appear in the iOS review flow.
          </p>
        </div>
      </div>

      {error && <div className="error">{error}</div>}

      <form className="formLayout" onSubmit={submit}>
        <div className="stack">
          <div className="builderCard">
            <div className="builderHeader">
              <span>Card 1</span>
              <span>Chinese to English</span>
            </div>
            <div className="builderBody">
              <div className="formGrid">
                <div className="field wide">
                  <label htmlFor="front">Term / prompt</label>
                  <textarea
                    id="front"
                    value={frontText}
                    onChange={(event) => setFrontText(event.target.value)}
                    placeholder="我想委婉问一下，明天之前能不能拿到？"
                  />
                </div>
                <div className="field wide">
                  <label htmlFor="answer">Definition / answer</label>
                  <textarea
                    id="answer"
                    value={answerText}
                    onChange={(event) => setAnswerText(event.target.value)}
                    placeholder="Any chance of getting it by tomorrow?"
                  />
                </div>
              </div>
            </div>
          </div>

          <div className="builderCard">
            <div className="builderHeader">
              <span>Phrase hints</span>
              <button type="button" className="ghost" onClick={() => setPhrases((current) => [...current, { ...emptyPhrase }])}>
                Add row
              </button>
            </div>
            <div className="builderBody">
              {phrases.map((phrase, index) => (
                <div className="phraseRow" key={index}>
                  <input
                    value={phrase.text}
                    onChange={(event) => updatePhrase(index, "text", event.target.value)}
                    placeholder="Any chance of + doing"
                  />
                  <input
                    value={phrase.note}
                    onChange={(event) => updatePhrase(index, "note", event.target.value)}
                    placeholder="有没有可能... / 委婉询问可能性"
                  />
                  <button type="button" className="ghost" onClick={() => removePhrase(index)}>
                    Remove
                  </button>
                </div>
              ))}
            </div>
          </div>

          <div className="actions">
            <button className="primaryButton" type="submit" disabled={saving}>
              {saving ? "Saving..." : "Save set"}
            </button>
            <button type="button" className="secondary" onClick={() => router.push("/cards")}>
              Cancel
            </button>
          </div>
        </div>

        <aside className="sidePanel">
          <div className="miniCard stack">
            <h3>Set details</h3>
            <div className="field">
              <label htmlFor="subject">Subject</label>
              <select id="subject" value={subjectID} onChange={(event) => setSubjectID(event.target.value)}>
                <option value="">Select subject</option>
                {subjects.map((subject) => (
                  <option key={subject.id} value={subject.id}>
                    {subject.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <span className="label">Set</span>
              <div className="checkboxGrid">
                {sets.map((set) => (
                  <label className="checkboxRow" key={set.id}>
                    <input
                      type="radio"
                      name="set"
                      checked={setID === set.id}
                      onChange={() => setSetID(set.id)}
                    />
                    <span>{set.name}</span>
                  </label>
                ))}
                {sets.length === 0 && <div className="empty">No sets in this subject.</div>}
              </div>
            </div>
          </div>

          <div className="miniCard quickCreate">
            <h3>Quick create</h3>
            <div className="field">
              <label htmlFor="newSubject">New subject</label>
              <input
                id="newSubject"
                value={newSubjectName}
                onChange={(event) => setNewSubjectName(event.target.value)}
                placeholder="English"
              />
              <button type="button" className="secondary" onClick={createSubject}>
                Add subject
              </button>
            </div>
            <div className="field">
              <label htmlFor="newSet">New set</label>
              <input
                id="newSet"
                value={newSetName}
                onChange={(event) => setNewSetName(event.target.value)}
                placeholder="Speaking"
                disabled={!subjectID}
              />
              <button type="button" className="secondary" onClick={createSet} disabled={!subjectID}>
                Add set
              </button>
            </div>
          </div>
        </aside>
      </form>
    </section>
  );
}
