"use client";

import { useEffect, useMemo, useState } from "react";
import { api, Subject, Tag } from "@/lib/api";

export default function SubjectsPage() {
  const [subjects, setSubjects] = useState<Subject[]>([]);
  const [selectedSubjectID, setSelectedSubjectID] = useState("");
  const [tags, setTags] = useState<Tag[]>([]);
  const [subjectName, setSubjectName] = useState("");
  const [tagName, setTagName] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    api
      .listSubjects()
      .then((items) => {
        setSubjects(items);
        if (items.length > 0) {
          setSelectedSubjectID(items[0].id);
        }
      })
      .catch((err: Error) => setError(err.message));
  }, []);

  useEffect(() => {
    if (!selectedSubjectID) {
      setTags([]);
      return;
    }
    api
      .listTags(selectedSubjectID)
      .then(setTags)
      .catch((err: Error) => setError(err.message));
  }, [selectedSubjectID]);

  const selectedSubject = useMemo(
    () => subjects.find((subject) => subject.id === selectedSubjectID),
    [subjects, selectedSubjectID]
  );

  async function createSubject() {
    const name = subjectName.trim();
    if (!name) {
      return;
    }
    try {
      const subject = await api.createSubject(name);
      setSubjects((current) => [...current, subject].sort((a, b) => a.name.localeCompare(b.name)));
      setSelectedSubjectID(subject.id);
      setSubjectName("");
      setError("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create subject");
    }
  }

  async function createTag() {
    const name = tagName.trim();
    if (!selectedSubjectID || !name) {
      return;
    }
    try {
      const tag = await api.createTag(selectedSubjectID, name);
      setTags((current) => [...current, tag].sort((a, b) => a.name.localeCompare(b.name)));
      setTagName("");
      setError("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create tag");
    }
  }

  return (
    <section>
      <div className="pageHero">
        <div>
          <p className="eyebrow">Subjects</p>
          <h1>Organize your sets</h1>
          <p className="subtle">
            Subjects group your study sets. Tags make each set easy to filter before review.
          </p>
        </div>
        <div className="heroCard">
          <div className="heroMetric">
            <div className="metric">
              <strong>{subjects.length}</strong>
              <span>subjects</span>
            </div>
            <div className="metric">
              <strong>{tags.length}</strong>
              <span>tags shown</span>
            </div>
          </div>
        </div>
      </div>

      {error && <div className="error">{error}</div>}

      <div className="libraryGrid">
        <div className="libraryPanel stack">
          <div>
            <h2>Subjects</h2>
            <p className="subtle">Choose a subject to manage its tags.</p>
          </div>
          <div className="quickCreate">
            <div className="field">
              <label htmlFor="subjectName">New subject</label>
              <div className="actions">
                <input
                  id="subjectName"
                  value={subjectName}
                  onChange={(event) => setSubjectName(event.target.value)}
                  placeholder="English"
                />
                <button className="secondary" onClick={createSubject}>
                  Add
                </button>
              </div>
            </div>
          </div>

          <div className="subjectList">
            {subjects.map((subject) => (
              <button
                className={`subjectCard ${selectedSubjectID === subject.id ? "subjectCardActive" : ""}`}
                key={subject.id}
                onClick={() => setSelectedSubjectID(subject.id)}
              >
                <strong>{subject.name}</strong>
                <span className="subjectStats">
                  <span>{subject.card_count} cards</span>
                  <span>{subject.due_count} due</span>
                </span>
              </button>
            ))}
            {subjects.length === 0 && <div className="empty">No subjects yet.</div>}
          </div>
        </div>

        <div className="libraryPanel stack">
          <div>
            <h2>{selectedSubject ? selectedSubject.name : "Tags"}</h2>
            <p className="subtle">Add focused tags for review filters and card creation.</p>
          </div>
          <div className="field">
            <label htmlFor="tagName">New tag</label>
            <div className="actions">
              <input
                id="tagName"
                value={tagName}
                onChange={(event) => setTagName(event.target.value)}
                placeholder="Speaking"
                disabled={!selectedSubjectID}
              />
              <button className="secondary" onClick={createTag} disabled={!selectedSubjectID}>
                Add
              </button>
            </div>
          </div>

          <div className="tagPanel">
            {tags.map((tag) => (
              <div className="tagRow" key={tag.id}>
                <strong>{tag.name}</strong>
                <span className="subjectStats">
                  <span>{tag.card_count} cards</span>
                  <span>{tag.due_count} due</span>
                </span>
              </div>
            ))}
            {tags.length === 0 && <div className="empty">No tags yet.</div>}
          </div>
        </div>
      </div>
    </section>
  );
}
