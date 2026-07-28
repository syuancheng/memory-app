"use client";

import { useEffect, useState } from "react";
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

  async function createSubject() {
    const name = subjectName.trim();
    if (!name) {
      return;
    }
    const subject = await api.createSubject(name);
    setSubjects((current) => [...current, subject].sort((a, b) => a.name.localeCompare(b.name)));
    setSelectedSubjectID(subject.id);
    setSubjectName("");
  }

  async function createTag() {
    const name = tagName.trim();
    if (!selectedSubjectID || !name) {
      return;
    }
    const tag = await api.createTag(selectedSubjectID, name);
    setTags((current) => [...current, tag].sort((a, b) => a.name.localeCompare(b.name)));
    setTagName("");
  }

  return (
    <section>
      <div className="pageHeader">
        <div>
          <h1>Subjects</h1>
          <p className="subtle">Create subjects and tags before uploading cards.</p>
        </div>
      </div>

      {error && <div className="error">{error}</div>}

      <div className="split">
        <div className="panel stack">
          <div className="field">
            <label htmlFor="subjectName">New Subject</label>
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
          <table className="table">
            <thead>
              <tr>
                <th>Subject</th>
                <th>Cards</th>
                <th>Due</th>
              </tr>
            </thead>
            <tbody>
              {subjects.map((subject) => (
                <tr key={subject.id} onClick={() => setSelectedSubjectID(subject.id)}>
                  <td>
                    <strong>{subject.name}</strong>
                  </td>
                  <td>{subject.card_count}</td>
                  <td>{subject.due_count}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="panel stack">
          <div className="field">
            <label htmlFor="tagName">New Tag</label>
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
          <table className="table">
            <thead>
              <tr>
                <th>Tag</th>
                <th>Cards</th>
                <th>Due</th>
              </tr>
            </thead>
            <tbody>
              {tags.map((tag) => (
                <tr key={tag.id}>
                  <td>
                    <strong>{tag.name}</strong>
                  </td>
                  <td>{tag.card_count}</td>
                  <td>{tag.due_count}</td>
                </tr>
              ))}
              {tags.length === 0 && (
                <tr>
                  <td colSpan={3} className="empty">
                    No tags yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}
