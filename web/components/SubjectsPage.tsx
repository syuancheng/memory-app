"use client";

import { useEffect, useMemo, useState } from "react";
import { api, Set, Subject } from "@/lib/api";

export default function SubjectsPage() {
  const [subjects, setSubjects] = useState<Subject[]>([]);
  const [selectedSubjectID, setSelectedSubjectID] = useState("");
  const [sets, setSets] = useState<Set[]>([]);
  const [subjectName, setSubjectName] = useState("");
  const [setName, setSetName] = useState("");
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
      setSets([]);
      return;
    }
    api
      .listSets(selectedSubjectID)
      .then(setSets)
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

  async function createSet() {
    const name = setName.trim();
    if (!selectedSubjectID || !name) {
      return;
    }
    try {
      const set = await api.createSet(selectedSubjectID, name);
      setSets((current) => [...current, set].sort((a, b) => a.name.localeCompare(b.name)));
      setSetName("");
      setError("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not create set");
    }
  }

  return (
    <section>
      <div className="pageHero">
        <div>
          <p className="eyebrow">Subjects</p>
          <h1>Organize your sets</h1>
          <p className="subtle">
            Subjects group your study sets. Sets make cards easy to filter before review.
          </p>
        </div>
        <div className="heroCard">
          <div className="heroMetric">
            <div className="metric">
              <strong>{subjects.length}</strong>
              <span>subjects</span>
            </div>
            <div className="metric">
              <strong>{sets.length}</strong>
              <span>sets shown</span>
            </div>
          </div>
        </div>
      </div>

      {error && <div className="error">{error}</div>}

      <div className="libraryGrid">
        <div className="libraryPanel stack">
          <div>
            <h2>Subjects</h2>
            <p className="subtle">Choose a subject to manage its sets.</p>
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
            <h2>{selectedSubject ? selectedSubject.name : "Sets"}</h2>
            <p className="subtle">Add focused sets for review filters and card creation.</p>
          </div>
          <div className="field">
            <label htmlFor="setName">New set</label>
            <div className="actions">
              <input
                id="setName"
                value={setName}
                onChange={(event) => setSetName(event.target.value)}
                placeholder="Speaking"
                disabled={!selectedSubjectID}
              />
              <button className="secondary" onClick={createSet} disabled={!selectedSubjectID}>
                Add
              </button>
            </div>
          </div>

          <div className="tagPanel">
            {sets.map((set) => (
              <div className="tagRow" key={set.id}>
                <strong>{set.name}</strong>
                <span className="subjectStats">
                  <span>{set.card_count} cards</span>
                  <span>{set.due_count} due</span>
                </span>
              </div>
            ))}
            {sets.length === 0 && <div className="empty">No sets yet.</div>}
          </div>
        </div>
      </div>
    </section>
  );
}
