export type Subject = {
  id: string;
  name: string;
  card_count: number;
  due_count: number;
};

export type Tag = {
  id: string;
  subject_id: string;
  name: string;
  card_count: number;
  due_count: number;
};

export type GrammarPhrase = {
  text: string;
  note: string;
};

export type AnswerToken = {
  text: string;
  index: number;
};

export type Card = {
  id: string;
  subject_id: string;
  subject_name?: string;
  tags: Tag[];
  card_type: string;
  direction: string;
  front_text: string;
  answer_text: string;
  grammar_phrases: GrammarPhrase[];
  answer_tokens: AnswerToken[];
  created_at: string;
  updated_at: string;
};

export type CardPayload = {
  subject_id: string;
  tag_ids: string[];
  card_type: string;
  direction: string;
  front_text: string;
  answer_text: string;
  grammar_phrases: GrammarPhrase[];
};

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080/api";

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers ?? {})
    },
    cache: "no-store"
  });

  if (!response.ok) {
    let message = `Request failed: ${response.status}`;
    try {
      const body = (await response.json()) as { error?: string };
      if (body.error) {
        message = body.error;
      }
    } catch {
      // Keep the status-based message.
    }
    throw new Error(message);
  }

  return response.json() as Promise<T>;
}

export const api = {
  listSubjects: () => request<Subject[]>("/subjects"),
  createSubject: (name: string) =>
    request<Subject>("/subjects", {
      method: "POST",
      body: JSON.stringify({ name })
    }),
  listTags: (subjectID: string) => request<Tag[]>(`/subjects/${subjectID}/tags`),
  createTag: (subjectID: string, name: string) =>
    request<Tag>(`/subjects/${subjectID}/tags`, {
      method: "POST",
      body: JSON.stringify({ name })
    }),
  listCards: (params: { subject_id?: string; tag_ids?: string[]; search?: string } = {}) => {
    const search = new URLSearchParams();
    if (params.subject_id) {
      search.set("subject_id", params.subject_id);
    }
    if (params.tag_ids && params.tag_ids.length > 0) {
      search.set("tag_ids", params.tag_ids.join(","));
    }
    if (params.search) {
      search.set("search", params.search);
    }
    const suffix = search.toString() ? `?${search.toString()}` : "";
    return request<Card[]>(`/cards${suffix}`);
  },
  getCard: (cardID: string) => request<Card>(`/cards/${cardID}`),
  createCard: (payload: CardPayload) =>
    request<Card>("/cards", {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  updateCard: (cardID: string, payload: CardPayload) =>
    request<Card>(`/cards/${cardID}`, {
      method: "PUT",
      body: JSON.stringify(payload)
    }),
  deleteCard: (cardID: string) =>
    request<{ status: string }>(`/cards/${cardID}`, {
      method: "DELETE"
    })
};
