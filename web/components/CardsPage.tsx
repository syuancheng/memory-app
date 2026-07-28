"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { api, Card, Subject, Tag } from "@/lib/api";

export default function CardsPage() {
  const [subjects, setSubjects] = useState<Subject[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [cards, setCards] = useState<Card[]>([]);
  const [subjectID, setSubjectID] = useState("");
  const [tagID, setTagID] = useState("");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    api
      .listSubjects()
      .then(setSubjects)
      .catch((err: Error) => setError(err.message));
  }, []);

  useEffect(() => {
    if (!subjectID) {
      setTags([]);
      setTagID("");
      return;
    }
    api
      .listTags(subjectID)
      .then(setTags)
      .catch((err: Error) => setError(err.message));
  }, [subjectID]);

  useEffect(() => {
    setLoading(true);
    api
      .listCards({
        subject_id: subjectID || undefined,
        tag_ids: tagID ? [tagID] : undefined,
        search: search || undefined
      })
      .then(setCards)
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  }, [subjectID, tagID, search]);

  const selectedSubject = useMemo(
    () => subjects.find((subject) => subject.id === subjectID),
    [subjects, subjectID]
  );

  async function deleteCard(cardID: string) {
    if (!confirm("Delete this card?")) {
      return;
    }
    await api.deleteCard(cardID);
    setCards((current) => current.filter((card) => card.id !== cardID));
  }

  return (
    <section>
      <div className="pageHeader">
        <div>
          <h1>Cards</h1>
          <p className="subtle">Upload and manage cards used by the iOS review app.</p>
        </div>
        <Link className="button" href="/cards/new">
          New Card
        </Link>
      </div>

      {error && <div className="error">{error}</div>}

      <div className="toolbar">
        <div className="field">
          <label htmlFor="search">Search</label>
          <input
            id="search"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Front or answer text"
          />
        </div>
        <div className="field">
          <label htmlFor="subject">Subject</label>
          <select id="subject" value={subjectID} onChange={(event) => setSubjectID(event.target.value)}>
            <option value="">All subjects</option>
            {subjects.map((subject) => (
              <option key={subject.id} value={subject.id}>
                {subject.name}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="tag">Tag</label>
          <select
            id="tag"
            value={tagID}
            onChange={(event) => setTagID(event.target.value)}
            disabled={!selectedSubject}
          >
            <option value="">All tags</option>
            {tags.map((tag) => (
              <option key={tag.id} value={tag.id}>
                {tag.name}
              </option>
            ))}
          </select>
        </div>
        <button className="secondary" onClick={() => { setSubjectID(""); setTagID(""); setSearch(""); }}>
          Reset
        </button>
      </div>

      <table className="table">
        <thead>
          <tr>
            <th>Front</th>
            <th>Answer</th>
            <th>Subject</th>
            <th>Tags</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {cards.map((card) => (
            <tr key={card.id}>
              <td>{card.front_text}</td>
              <td>{card.answer_text}</td>
              <td>{card.subject_name}</td>
              <td>
                <div className="tagList">
                  {card.tags.map((tag) => (
                    <span className="tag" key={tag.id}>
                      {tag.name}
                    </span>
                  ))}
                </div>
              </td>
              <td>
                <div className="actions">
                  <Link className="secondary" href={`/cards/${card.id}/edit`}>
                    Edit
                  </Link>
                  <button className="danger" onClick={() => deleteCard(card.id)}>
                    Delete
                  </button>
                </div>
              </td>
            </tr>
          ))}
          {!loading && cards.length === 0 && (
            <tr>
              <td colSpan={5} className="empty">
                No cards found.
              </td>
            </tr>
          )}
          {loading && (
            <tr>
              <td colSpan={5} className="empty">
                Loading cards...
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </section>
  );
}
