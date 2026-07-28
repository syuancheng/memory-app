"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, CardPayload, GrammarPhrase, Subject, Tag } from "@/lib/api";

type Props = {
  mode: "new" | "edit";
  cardID?: string;
};

const emptyPhrase: GrammarPhrase = { text: "", note: "" };

export default function CardForm({ mode, cardID }: Props) {
  const router = useRouter();
  const [subjects, setSubjects] = useState<Subject[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [subjectID, setSubjectID] = useState("");
  const [tagIDs, setTagIDs] = useState<string[]>([]);
  const [frontText, setFrontText] = useState("");
  const [answerText, setAnswerText] = useState("");
  const [phrases, setPhrases] = useState<GrammarPhrase[]>([{ ...emptyPhrase }]);
  const [newSubjectName, setNewSubjectName] = useState("");
  const [newTagName, setNewTagName] = useState("");
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
        setTagIDs(card.tags.map((tag) => tag.id));
        setFrontText(card.front_text);
        setAnswerText(card.answer_text);
        setPhrases(card.grammar_phrases.length > 0 ? card.grammar_phrases : [{ ...emptyPhrase }]);
      })
      .catch((err: Error) => setError(err.message));
  }, [mode, cardID]);

  useEffect(() => {
    if (!subjectID) {
      setTags([]);
      setTagIDs([]);
      return;
    }
    api
      .listTags(subjectID)
      .then((items) => {
        setTags(items);
        setTagIDs((current) => current.filter((id) => items.some((tag) => tag.id === id)));
      })
      .catch((err: Error) => setError(err.message));
  }, [subjectID]);

  async function createSubject() {
    const name = newSubjectName.trim();
    if (!name) {
      return;
    }
    const subject = await api.createSubject(name);
    setSubjects((current) => [...current, subject].sort((a, b) => a.name.localeCompare(b.name)));
    setSubjectID(subject.id);
    setNewSubjectName("");
  }

  async function createTag() {
    const name = newTagName.trim();
    if (!subjectID || !name) {
      return;
    }
    const tag = await api.createTag(subjectID, name);
    setTags((current) => [...current, tag].sort((a, b) => a.name.localeCompare(b.name)));
    setTagIDs((current) => [...current, tag.id]);
    setNewTagName("");
  }

  function toggleTag(tagID: string) {
    setTagIDs((current) =>
      current.includes(tagID) ? current.filter((id) => id !== tagID) : [...current, tagID]
    );
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
    setSaving(true);
    const payload: CardPayload = {
      subject_id: subjectID,
      tag_ids: tagIDs,
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
      <div className="pageHeader">
        <div>
          <h1>{mode === "edit" ? "Edit Card" : "New Card"}</h1>
          <p className="subtle">Create English review material for the iOS app.</p>
        </div>
      </div>

      {error && <div className="error">{error}</div>}

      <form className="panel stack" onSubmit={submit}>
        <div className="formGrid">
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
            <label htmlFor="newSubject">Create Subject</label>
            <div className="actions">
              <input
                id="newSubject"
                value={newSubjectName}
                onChange={(event) => setNewSubjectName(event.target.value)}
                placeholder="English"
              />
              <button type="button" className="secondary" onClick={createSubject}>
                Add
              </button>
            </div>
          </div>

          <div className="field wide">
            <span className="label">Tags</span>
            <div className="checkboxGrid">
              {tags.map((tag) => (
                <label className="checkboxRow" key={tag.id}>
                  <input
                    type="checkbox"
                    checked={tagIDs.includes(tag.id)}
                    onChange={() => toggleTag(tag.id)}
                  />
                  <span>{tag.name}</span>
                </label>
              ))}
            </div>
          </div>
          <div className="field wide">
            <label htmlFor="newTag">Create Tag</label>
            <div className="actions">
              <input
                id="newTag"
                value={newTagName}
                onChange={(event) => setNewTagName(event.target.value)}
                placeholder="Work Expression"
                disabled={!subjectID}
              />
              <button type="button" className="secondary" onClick={createTag} disabled={!subjectID}>
                Add
              </button>
            </div>
          </div>

          <div className="field wide">
            <label htmlFor="front">Front</label>
            <textarea
              id="front"
              value={frontText}
              onChange={(event) => setFrontText(event.target.value)}
              placeholder="我想委婉问一下，明天之前能不能拿到？"
            />
          </div>
          <div className="field wide">
            <label htmlFor="answer">Answer</label>
            <textarea
              id="answer"
              value={answerText}
              onChange={(event) => setAnswerText(event.target.value)}
              placeholder="Any chance of getting it by tomorrow?"
            />
          </div>
        </div>

        <div>
          <div className="pageHeader">
            <div>
              <h1 style={{ fontSize: 20 }}>Grammar / Phrases</h1>
              <p className="subtle">Each row becomes a hint on the iOS back side.</p>
            </div>
            <button type="button" className="secondary" onClick={() => setPhrases((current) => [...current, { ...emptyPhrase }])}>
              Add row
            </button>
          </div>
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

        <div className="actions">
          <button className="button" type="submit" disabled={saving}>
            {saving ? "Saving..." : "Save Card"}
          </button>
          <button type="button" className="secondary" onClick={() => router.push("/cards")}>
            Cancel
          </button>
        </div>
      </form>
    </section>
  );
}
